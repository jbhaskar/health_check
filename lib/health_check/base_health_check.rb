module BaseHealthCheck
  def create_error(check_type, error_message)
    { 
      error: true,
      check_type: check_type,
      error_message: error_message
    }
  end
end
