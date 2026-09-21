# ==============================================================================
# AFT Ouroboros: Flujo de Síntesis e Implementación Out-of-Context (OOC)
# Dispositivo Objetivo: AMD Kria K26 SOM (xck26-sfvc784-2LV-c)
# ==============================================================================

set PROJECT_NAME "ouroboros_descartes_core"
set PART "xck26-sfvc784-2LV-c"
set REPORT_DIR "./reports_kv260"

file mkdir $REPORT_DIR

# 1. Leer fuentes SystemVerilog del núcleo
read_verilog -sv descartes_acc_unit.sv
read_verilog -sv descartes_gemv_engine.sv
read_verilog -sv descartes_bram_16kb.sv
read_verilog -sv descartes_operator_top.sv

# 2. Leer restricciones de temporización
read_xdc constraints_250mhz.xdc

# 3. Síntesis fuera de contexto (Out-of-Context para IP Core sin I/O buffers externos)
puts "========================================================================"
puts "[+] Iniciando Sintesis Vivado: descartes_operator_top a 250 MHz..."
puts "========================================================================"
synth_design -top descartes_operator_top -part $PART -mode out_of_context

# Reporte post-síntesis
report_utilization -file "${REPORT_DIR}/post_synth_utilization.rpt"
report_timing_summary -file "${REPORT_DIR}/post_synth_timing.rpt"

# 4. Optimización de lógica
opt_design

# 5. Ubicación física (Place)
puts "========================================================================"
puts "[+] Ejecutando Place..."
puts "========================================================================"
place_design
report_utilization -file "${REPORT_DIR}/post_place_utilization.rpt"

# 6. Optimización física post-place
phys_opt_design

# 7. Ruteo (Route)
puts "========================================================================"
puts "[+] Ejecutando Route..."
puts "========================================================================"
route_design

# 8. Reportes Finales Implementados (Métricas Reales de Silicio)
report_utilization -file "${REPORT_DIR}/final_utilization.rpt"
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -file "${REPORT_DIR}/final_timing.rpt"
report_power -file "${REPORT_DIR}/final_power.rpt"
report_clock_utilization -file "${REPORT_DIR}/final_clock_utilization.rpt"

# 9. Escritura de Checkpoint de Diseño (DCP)
write_checkpoint -force "${REPORT_DIR}/descartes_operator_top_routed.dcp"

puts "========================================================================"
puts "[+] FLUJO DE SINTESIS Y P&R COMPLETADO CON EXITO."
puts "[+] Reportes generados en: ${REPORT_DIR}/"
puts "========================================================================"
exit
