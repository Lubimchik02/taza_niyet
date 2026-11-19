-- Минимальный возраст 13 лет (как в приложении: AuthValidators.minAge). Год рождения считается по худшему случаю.
create function profiles_min_age() returns trigger language plpgsql as $$
begin
  if extract(year from now())::int - new.birth_year - 1 < 13 then raise exception 'too_young'; end if;
  return new;
end $$;
create trigger profiles_min_age before insert on profiles for each row execute function profiles_min_age();
