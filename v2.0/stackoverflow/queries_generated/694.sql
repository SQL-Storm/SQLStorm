-- {"query": "694.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3125} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location,
    extract(year from u.creationdate) as create_year
  from users u
  where u.creationdate >= (
    select max(creationdate) - interval '365 days' from users
  )
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score,0)) as total_post_score,
    avg(nullif(p.viewcount,0)) as avg_views_nonzero
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
comment_aggr as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(coalesce(c.score,0)) as comment_score_sum,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.userid is not null
  group by c.userid
),
badge_aggr as (
  select
    b.userid as user_id,
    count(*) as badges_total,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  group by b.userid
),
post_intervals as (
  select
    p.owneruserid as user_id,
    p.id as post_id,
    p.posttypeid,
    p.creationdate,
    lag(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as prev_creation,
    lead(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as next_creation
  from posts p
  where p.owneruserid is not null
),
post_gaps as (
  select
    user_id,
    avg(extract(epoch from (creationdate - prev_creation))) as avg_gap_seconds_prev,
    avg(extract(epoch from (next_creation - creationdate))) as avg_gap_seconds_next
  from post_intervals
  where prev_creation is not null or next_creation is not null
  group by user_id
),
question_quality as (
  select
    q.owneruserid as user_id,
    count(*) as questions_total,
    sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_count,
    avg(q.score) as avg_q_score,
    percentile_disc(0.9) within group (order by q.viewcount) as p90_q_views,
    sum(case when q.closeddate is not null then 1 else 0 end) as closed_q
  from posts q
  where q.posttypeid = 1 and q.owneruserid is not null
  group by q.owneruserid
),
answer_quality as (
  select
    a.owneruserid as user_id,
    count(*) as answers_total,
    avg(a.score) as avg_a_score,
    sum(case when exists (
      select 1
      from posts q
      where q.id = a.parentid
        and q.acceptedanswerid = a.id
    ) then 1 else 0 end) as accepted_by_op_count
  from posts a
  where a.posttypeid = 2 and a.owneruserid is not null
  group by a.owneruserid
),
tag_exposure as (
  select
    p.owneruserid as user_id,
    lower(trim(tg)) as tag_name,
    count(*) as tag_hits
  from posts p
  cross join lateral unnest(
    case
      when p.posttypeid = 1 and p.tags is not null and length(p.tags) >= 2
      then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
      else array[]::varchar[]
    end
  ) as tg
  where p.owneruserid is not null
  group by p.owneruserid, lower(trim(tg))
),
top_tags as (
  select distinct on (user_id)
    user_id,
    tag_name,
    tag_hits
  from (
    select
      te.user_id,
      te.tag_name,
      te.tag_hits,
      row_number() over (partition by te.user_id order by te.tag_hits desc, te.tag_name) as rn
    from tag_exposure te
  ) s
  where rn <= 3
  order by user_id, tag_hits desc, tag_name
),
top_tags_pivot as (
  select
    user_id,
    max(case when rn = 1 then tag_name end) as top_tag_1,
    max(case when rn = 1 then tag_hits end) as top_tag_1_hits,
    max(case when rn = 2 then tag_name end) as top_tag_2,
    max(case when rn = 2 then tag_hits end) as top_tag_2_hits,
    max(case when rn = 3 then tag_name end) as top_tag_3,
    max(case when rn = 3 then tag_hits end) as top_tag_3_hits
  from (
    select
      te.user_id,
      te.tag_name,
      te.tag_hits,
      row_number() over (partition by te.user_id order by te.tag_hits desc, te.tag_name) as rn
    from tag_exposure te
  ) x
  where rn <= 3
  group by user_id
),
vote_aggr as (
  select
    v.userid as voter_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounties_events,
    sum(coalesce(v.bountyamount,0)) as bounty_amount_total
  from votes v
  where v.userid is not null
  group by v.userid
),
post_vote_received as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_received,
    count(*) filter (where v.votetypeid = 3) as downvotes_received
  from posts p
  left join votes v on v.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
dup_links as (
  select
    pl.postid as post_id,
    pl.relatedpostid as related_id,
    pl.creationdate as link_date
  from postlinks pl
  where pl.linktypeid = 3
),
dup_activity as (
  select
    coalesce(p.owneruserid, pr.owneruserid) as user_id,
    count(distinct case when p.posttypeid = 1 then p.id end) as user_questions_marked_duplicate,
    count(distinct case when pr.posttypeid = 1 then pr.id end) as user_originals_with_dupes
  from dup_links d
  left join posts p on p.id = d.post_id
  left join posts pr on pr.id = d.related_id
  group by coalesce(p.owneruserid, pr.owneruserid)
),
closures as (
  select
    ph.postid,
    max(ph.creationdate) as last_closed_at,
    max(case when ph.comment ~ '^[0-9]+' then ph.comment::int end) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid
),
close_reason_name as (
  select
    c.postid,
    crt.name as close_reason_name
  from closures c
  left join closerreasontypes crt on crt.id = c.last_close_reason_id
),
post_edit_counts as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as content_edits,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_applied
  from posthistory ph
  group by ph.postid
),
user_post_edit_aggr as (
  select
    p.owneruserid as user_id,
    sum(coalesce(pe.content_edits,0)) as total_content_edits,
    sum(coalesce(pe.suggested_applied,0)) as total_suggested_applied
  from posts p
  left join post_edit_counts pe on pe.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
ranked_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.norm_location,
    ua.q_count,
    ua.a_count,
    qa.questions_total,
    aa.answers_total,
    pv.upvotes_received,
    pv.downvotes_received,
    va.upvotes_cast,
    va.downvotes_cast,
    coalesce(qa.accepted_count,0) as accepted_q_count,
    coalesce(aa.accepted_by_op_count,0) as accepted_a_count,
    coalesce(ua.total_post_score,0) as total_post_score,
    coalesce(ua.avg_views_nonzero,0) as avg_views_nonzero,
    coalesce(qa.avg_q_score,0) as avg_q_score,
    coalesce(aa.avg_a_score,0) as avg_a_score,
    coalesce(qa.p90_q_views,0) as p90_q_views,
    coalesce(qa.closed_q,0) as closed_q,
    coalesce(pe.total_content_edits,0) as total_content_edits,
    coalesce(pe.total_suggested_applied,0) as total_suggested_applied,
    coalesce(pg.avg_gap_seconds_prev,0) as avg_gap_seconds_prev,
    coalesce(pg.avg_gap_seconds_next,0) as avg_gap_seconds_next,
    coalesce(ba.badges_total,0) as badges_total,
    coalesce(ba.gold_badges,0) as gold_badges,
    coalesce(ba.silver_badges,0) as silver_badges,
    coalesce(ba.bronze_badges,0) as bronze_badges,
    coalesce(ba.tag_badges,0) as tag_badges
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join question_quality qa on qa.user_id = ru.user_id
  left join answer_quality aa on aa.user_id = ru.user_id
  left join post_vote_received pv on pv.user_id = ru.user_id
  left join vote_aggr va on va.voter_id = ru.user_id
  left join user_post_edit_aggr pe on pe.user_id = ru.user_id
  left join post_gaps pg on pg.user_id = ru.user_id
  left join badge_aggr ba on ba.user_id = ru.user_id
),
scored as (
  select
    r.*,
    coalesce(
      0.40 * ln(1 + greatest(r.reputation,0)) +
      0.15 * ln(1 + greatest(r.q_count,0)) +
      0.20 * ln(1 + greatest(r.a_count,0)) +
      0.10 * ln(1 + greatest(r.upvotes_received - r.downvotes_received,0)) +
      0.05 * ln(1 + greatest(r.badges_total + r.gold_badges*2 + r.silver_badges*1.5,0)) +
      0.05 * ln(1 + greatest(r.total_content_edits,0)) +
      0.05 * ln(1 + greatest(r.accepted_a_count,0))
    , 0) as perf_score
  from ranked_users r
),
filter_rank as (
  select
    s.*,
    row_number() over (order by s.perf_score desc nulls last, s.reputation desc, s.user_id) as global_rank,
    dense_rank() over (partition by s.norm_location order by s.perf_score desc nulls last, s.reputation desc, s.user_id) as region_rank
  from scored s
  where coalesce(s.q_count,0) + coalesce(s.a_count,0) >= 5
)
select
  fr.user_id,
  fr.displayname,
  fr.norm_location,
  fr.reputation,
  fr.q_count,
  fr.a_count,
  fr.questions_total,
  fr.answers_total,
  fr.upvotes_received,
  fr.downvotes_received,
  fr.upvotes_cast,
  fr.downvotes_cast,
  fr.accepted_q_count,
  fr.accepted_a_count,
  fr.avg_q_score,
  fr.avg_a_score,
  fr.p90_q_views,
  fr.closed_q,
  fr.total_content_edits,
  fr.total_suggested_applied,
  round(fr.avg_gap_seconds_prev)::bigint as avg_gap_seconds_prev,
  round(fr.avg_gap_seconds_next)::bigint as avg_gap_seconds_next,
  fr.badges_total,
  fr.gold_badges,
  fr.silver_badges,
  fr.bronze_badges,
  fr.tag_badges,
  coalesce(tt.top_tag_1,'') as top_tag_1,
  coalesce(tt.top_tag_1_hits,0) as top_tag_1_hits,
  coalesce(tt.top_tag_2,'') as top_tag_2,
  coalesce(tt.top_tag_2_hits,0) as top_tag_2_hits,
  coalesce(tt.top_tag_3,'') as top_tag_3,
  coalesce(tt.top_tag_3_hits,0) as top_tag_3_hits,
  dn.close_reason_name,
  fr.perf_score,
  fr.global_rank,
  fr.region_rank
from filter_rank fr
left join top_tags_pivot tt on tt.user_id = fr.user_id
left join (
  select distinct on (p.owneruserid)
    p.owneruserid as user_id,
    crn.close_reason_name
  from posts p
  left join close_reason_name crn on crn.postid = p.id
  where p.posttypeid = 1 and p.owneruserid is not null and crn.close_reason_name is not null
  order by p.owneruserid, p.creationdate desc
) dn on dn.user_id = fr.user_id
order by fr.global_rank
limit 200;