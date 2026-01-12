/******************************************************************
 EMOVI 2015 — Limpieza mínima, construcción de variables y modelos
******************************************************************/

*---------------------------------------------------------------*
* INICIO
*---------------------------------------------------------------*
clear all
set more off

* Paquetes necesarios (tabla)
cap which esttab
if _rc ssc install estout, replace

* Cargar datos
use "--", clear // Data not included
compress

*---------------------------------------------------------------*
* 1) AÑOS DE EDUCACIÓN DE INDIVIDUO I
*---------------------------------------------------------------*
capture drop anios_edu
gen double anios_edu = .
replace anios_edu = 0                   if inlist(p9,1,2)              // ninguno / preescolar
replace anios_edu = min(p10,6)          if p9==3                        // primaria (máx 6)
replace anios_edu = 6  + min(p10,3)     if p9==4                        // secundaria (3)
replace anios_edu = 9  + min(p10,3)     if p9==5                        // media superior (3)
replace anios_edu = 12 + min(p10,3)     if p9==6                        // normal / técnico sup. (~3)
replace anios_edu = 12 + min(p10,4)     if p9==7                        // licenciatura (~4)
replace anios_edu = 16 + min(p10,2)     if p9==8                        // maestría (~2)
replace anios_edu = 18 + min(p10,3)     if p9==9                        // doctorado (~3)

*---------------------------------------------------------------*
* 2) AÑOS DE EDUCACIÓN DE PADRE / MADRE 
*---------------------------------------------------------------*
capture drop anios_edu_padre anios_edu_madre

gen double anios_edu_padre = .
replace anios_edu_padre = 0   if inlist(p88a8,1,2)
replace anios_edu_padre = 6   if p88a8==3
replace anios_edu_padre = 9   if p88a8==4
replace anios_edu_padre = 12  if p88a8==5
replace anios_edu_padre = 15  if p88a8==6
replace anios_edu_padre = 16  if p88a8==7
replace anios_edu_padre = 18  if p88a8==8
replace anios_edu_padre = 21  if p88a8==9

gen double anios_edu_madre = .
replace anios_edu_madre = 0   if inlist(p88b8,1,2)
replace anios_edu_madre = 6   if p88b8==3
replace anios_edu_madre = 9   if p88b8==4
replace anios_edu_madre = 12  if p88b8==5
replace anios_edu_madre = 15  if p88b8==6
replace anios_edu_madre = 16  if p88b8==7
replace anios_edu_madre = 18  if p88b8==8
replace anios_edu_madre = 21  if p88b8==9

*---------------------------------------------------------------*
* 3) INGRESO MENSUAL y LOG-INGRESO
*---------------------------------------------------------------*
capture drop ing_mensual ln_ing_mens
gen double ing_mensual = p63
destring ing_mensual, replace force
replace  ing_mensual = . if ing_mensual <= 0
gen double ln_ing_mens = ln(ing_mensual)

*---------------------------------------------------------------*
* 4) CONSTRUCCIÓN DE EXPERIENCIA 
*---------------------------------------------------------------*
capture drop exper exper2
gen double exper  = max(p4 - anios_edu - 6, 0)
gen double exper2 = exper^2

keep if inrange(p4,25,60) & !missing(ln_ing_mens, anios_edu, exper, exper2)

*---------------------------------------------------------------*
* 5) GRÁFICOS 
*---------------------------------------------------------------*
preserve
    histogram ing_mensual,  percent bin(50) ///
        title("Distribución del ingreso mensual") ///
        xtitle("Ingreso mensual") ytitle("Porcentaje")
    histogram ln_ing_mens, percent bin(50) ///
        title("Distribución del log ingreso mensual") ///
        xtitle("Log ingreso mensual") ytitle("Porcentaje")
    kdensity ing_mensual, title("Densidad del ingreso mensual")
    twoway (scatter ln_ing_mens anios_edu, msize(vsmall) mcolor(blue%40)) ///
           (lfit ln_ing_mens anios_edu,  lcolor(red)   lwidth(medthick)), ///
           title("Log ingreso y educación") ///
           xtitle("Años de educación") ytitle("Log ingreso mensual")
restore

*---------------------------------------------------------------*
* 6) TRATAMIENTO DE OUTLIERS EN INGRESO
*---------------------------------------------------------------*

quietly su ln_ing_mens, detail
tempname p1 p99
scalar `p1'  = r(p1)
scalar `p99' = r(p99)

* Recorte eliminación de extremos
keep if ln_ing_mens >= `p1' & ln_ing_mens <= `p99'


*---------------------------------------------------------------*
* 7) CONTROLES, MODELOS y TABLA 
*---------------------------------------------------------------*

* Controles 
local dep    ln_ing_mens
local baseX  anios_edu exper exper2
local ctrls  i.p3 i.cve_edo i.p41

* Limpiar 
eststo clear

* Modelo 1: OLS 
eststo OLS: regress `dep' `baseX' `ctrls', vce(robust)

* Modelo 2: IV — educación instrumentada con educación de padres
eststo IV_both: ivregress 2sls `dep' (anios_edu = anios_edu_padre anios_edu_madre) ///
    exper exper2 `ctrls', vce(robust)

* Diagnósticos IV 
estat endogenous            // Hausman: H0 educación exógena
estat overid                // Sargan/Hansen (si >1 IV)
estat firststage            // Fuerza de instrumentos (F y R2 parcial)

* Modelo 3: IV — sólo educación del padre
eststo IV_father: ivregress 2sls `dep' (anios_edu = anios_edu_padre) ///
    exper exper2 `ctrls', vce(robust)

* Diagnósticos
estat endogenous
estat firststage

* Tabla comparativa (MCO vs IV)
esttab OLS IV_both IV_father, ///
    title("Retornos a la educación: OLS vs IV") ///
    b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(anios_edu exper exper2) ///
    stats(N r2, labels("Observaciones" "R^2")) ///
    label compress

*---------------------------------------------------------------*
* 8) Guardar base procesada
*---------------------------------------------------------------*
save "emovi2015_adultos_limpio.dta", replace
