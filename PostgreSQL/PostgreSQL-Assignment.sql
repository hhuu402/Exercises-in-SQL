--Q1
--List all persons that are neither clients nor staff members. Order the result by pid in ascending order
create or replace view Q1(pid, firstname, lastname) as
	select pid, firstname, lastname from person
	where pid not in (select pid from client)
	and pid not in (select pid from staff)
	order by pid asc;


--Q2
--List all persons (including staff and clients) who have never been insured (wholly or jointly) by an enforced policy from the company. Order the result by pid in ascending order
create or replace view Q2(pid, firstname, lastname) as
	select pid, firstname, lastname from person
	where pid not in
	(select pid from client
		where cid in 
		(select cid from insured_by
			where pno in
			(select pno from policy where status = 'E')))
	order by pid asc;


--Q3
--For each vehicle brand, list the vehicle insured by the most expensive policy (the premium, i.e., the sum of its approved coverages' rates). Include only the past and current enforced policies. Order the result by brand, and then by vehicle id, pno if there are ties, all in ascending order.
create or replace view Q3sum(brand, id, pno, premium_rate) as
	select i.brand, i.id, p.pno, sum(r.rate) as premium_rate from insured_item i
	join policy p on i.id = p.id and p.status = 'E' and p.effectivedate < now()
	join coverage c on p.pno = c.pno
	join rating_record r on c.coid = r.coid and r.status = 'A'
	group by i.brand, i.id, p.pno;

create or replace view Q3(brand, vid, pno, premium) as
	select * from q3sum q
	where q.premium_rate in
	(select max(q.premium_rate) from q3sum q
		group by brand)
	order by brand, q.id, pno desc;


--Q4
--List all the staff members who have not sell, rate or underwrite any policies that are/were eventually enforced. Note that policy.sid records the staff who sold the policy (i.e., the agent). Order the result by pid (i.e., Persion id) in ascending order.
create or replace view q4helper(pid, firstname, lastname) as
	(select distinct pe.pid, pe.firstname, pe.lastname from staff s
	join person pe on pe.pid = s.pid
	join policy p on s.sid = p.sid and p.status = 'E' and p.effectivedate < now())
	union 
	((select distinct p.pid, p.firstname, p.lastname from staff s
	join person p on p.pid = s.pid
	join underwritten_by ub on ub.sid = s.sid
	join underwriting_record ur on ur.urid = ub.urid and ur.status in ('A', 'O')
	)
	union
	(select distinct p.pid, p.firstname, p.lastname from staff s
	join person p on p.pid = s.pid
	join rated_by rb on rb.sid = s.sid
	join rating_record rr on rr.rid = rb.rid and rr.status in ('A', 'O')
	))
	order by pid asc;

create or replace view Q4(pid, firstname, lastname) as
	select distinct p.pid, p.firstname, p.lastname from person p
	join staff s on s.pid = p.pid
	where p.pid not in 
		(select pid from q4helper)
	order by p.pid asc;


--Q5
--For each suburb (by suburb name) in NSW, compute the number of enforced policies that have been sold to the policy holders living in the suburb (regardless of the policy effective and expiry dates). Order the result by Number of Policies (npolicies), then by suburb, in ascending order. Exclude suburbs with no sold policies. Furthermore, suburb names are output in all uppercase.
create or replace view Q5(suburb, npolicies) as
	select upper(pe.suburb), count(p.pno) as npolicies from policy p
	join insured_by i on i.pno = p.pno and p.status = 'E'
	join client c on c.cid = i.cid
	join person pe on pe.pid = c.pid and pe.state = 'NSW'
	group by pe.suburb
	order by npolicies, suburb;


--Q6
--Find all past and current enforced policies which are rated, underwritten, and sold by the same staff member, and not involved any others at all. Order the result by pno in ascending order.
create or replace view Q6(pno, ptype, pid, firstname, lastname) as
	select distinct p.pno, p.ptype, pe.pid, pe.firstname, pe.lastname from person pe
	join staff s on s.pid = pe.pid
	join policy p on p.sid = s.sid and p.status = 'E' and p.effectivedate < now()
	left join underwriting_record ur on ur.pno = p.pno where ur.status in ('A')
	and s.sid in
		(select rb.sid from rated_by rb natural join rating_record rr where rr.status not in ('A'))
	;


--Q7
--The company would like to speed up the turnaround time of approving a policy and wants to find the enforced policy with the longest time between the first rater rating a coverage of the policy (regardless of the rating status), and the last underwriter approving the policy. Find such a policy (or policies if there is more than one policy with the same longest time) and output the details as specified below. Order the result by pno in ascending order.
create or replace view q7helper(pno, ptime) as
	select p.pno, age(wdate, rdate)from policy p
	join underwriting_record ur on ur.pno = p.pno and ur.status = 'A'
	join underwritten_by ub on ub.urid = ur.urid
	join coverage c on c.pno = p.pno
	join rating_record rr on rr.coid = c.coid
	join rated_by rb on rb.rid = rr.rid
	;

create or replace view q7max(pno, ptime) as
	select pno, max(ptime) from q7helper
	where q7helper.ptime in
		(select max(ptime) from q7helper)
	group by pno;

create or replace view Q7(pno, ptype, effectivedate, expirydate, agreedvalue) as
	select p.pno, p.ptype, p.effectivedate, p.expirydate, p.agreedvalue from policy p
	join q7max q on q.pno = p.pno
	order by p.pno asc;


--Q8
--List the staff members (their firstname, a space and then the lastname as one column called name) who have successfully sold policies (i.e., enforced policies) that only cover one brand of vehicle. Order the result by pid in ascending order.
create or replace view q8helper(sid, pid, nbrand) as
	select s.sid, pe.pid, count(distinct v.brand) from insured_item v
	join policy p on v.id = p.id and p.status = 'E'
	join staff s on s.sid = p.sid
	join person pe on pe.pid = s.pid
	group by s.sid, pe.pid
	;

create or replace view Q8(pid, name, brand) as
	select distinct pe.pid, concat(pe.firstname, ' ', pe.lastname) "name", v.brand from person pe
	join q8helper q on q.pid = pe.pid and q.nbrand = 1
	join policy p on p.sid = q.sid
	join insured_item v on p.id = v.id
	order by pid asc;


--Q9
--List clients (their firstname, a space and then the lastname as one column called name) who hold policies that cover all brands of vehicles recorded in the database. Ignore the policy status and include the past and current policies. Order the result by pid in ascending order.
create or replace view q9helper(pid, nbrand) as
	select pe.pid, count(distinct v.brand) from insured_item v
	join policy p on v.id = p.id and p.effectivedate <= now()
	join insured_by ib on ib.pno = p.pno
	join client c on c.cid = ib.cid
	join person pe on pe.pid = c.pid
	group by pe.pid;

create or replace view Q9(pid, name) as
	select pe.pid, concat(pe.firstname, ' ', pe.lastname) "name" from person pe
	join q9helper q on q.pid = pe.pid and q.nbrand =
		(select count(distinct brand) from insured_item)
	order by pid asc;


--Q10
--Create a function that returns the total number of (distinct) staff that have worked (i.e., sells, rates, underwrites) on the given policy (ignore its status)
create or replace function staffcount(pno integer)
	returns integer
as $$
declare
	x integer;
begin
	select count(distinct sid) into x
	from (select c.pno, rb.sid from rated_by rb
			join rating_record rr on rb.rid = rr.rid
			join coverage c on rr.coid = c.coid
			where c.pno = $1
		union
		select ur.pno, ub.sid from underwritten_by ub
    		join underwriting_record ur on ub.urid = ur.urid
            join policy p on ur.pno = p.pno
			where ur.pno = $1
		union
		select p.pno, p.sid from policy p
			where p.pno = $1
		) as foo;

	return x;

end;
$$ language plpgsql;