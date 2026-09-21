# Reloj primario del núcleo a 250 MHz (Periodo: 4.0 ns)
create_clock -period 4.000 -name aclk -waveform {0.000 2.000} [get_ports aclk]

# Retardo máximo de entrada y salida virtual para síntesis fuera de contexto (OOC)
set_input_delay -clock aclk -max 1.000 [get_ports {s_axis_tvalid s_axis_tlast s_axis_tdata* m_axis_tready aresetn}]
set_input_delay -clock aclk -min 0.200 [get_ports {s_axis_tvalid s_axis_tlast s_axis_tdata* m_axis_tready aresetn}]

set_output_delay -clock aclk -max 1.000 [get_ports {s_axis_tready m_axis_tvalid m_axis_tlast m_axis_tdata*}]
set_output_delay -clock aclk -min 0.200 [get_ports {s_axis_tready m_axis_tvalid m_axis_tlast m_axis_tdata*}]
