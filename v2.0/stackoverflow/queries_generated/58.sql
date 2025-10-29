-- {"query": "58.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2449} 
with
-- pick a recent-ish activity window
params as (
  select
    now() - interval '365 days' as since_date,
    0.05::float as top_fraction
),
-- active users with engagement metrics
user_activity as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(u.location, 'Unknown') as location,
    sum(case when p.posttypeid in (1,2) then 1 else 0 end) filter (where p.creationdate >= (select since_date from params)) as posts_last_year,
    count(distinct c.id) filter (where c.creationdate >= (select since_date from params)) as comments_last_year,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) filter (where v.creationdate >= (select since_date from params)) as net_votes_last_year,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join votes v on v.userid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location
),
-- window ranks for percentile-based thresholds
user_ranks as (
  select
    ua.*,
    percent_rank() over (order by coalesce(ua.net_votes_last_year,0)) as pr_net_votes,
    percent_rank() over (order by coalesce(ua.posts_last_year,0)) as pr_posts,
    ntile(10) over (order by coalesce(ua.reputation,0) desc) as rep_decile
  from user_activity ua
),
-- posts and their engagement signatures
post_engagement as (
  select
    p.id as post_id,
    p.posttypeid,
    p.owneruserid,
    p.parentid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.title,
    p.tags,
    exists (
      select 1
      from posthistory ph
      where ph.postid = p.id
        and ph.posthistorytypeid in (5,6,24) -- edits
        and ph.creationdate >= p.creationdate
        and ph.creationdate < p.creationdate + interval '2 days'
    ) as edited_early,
    (
      select count(*)
      from votes v
      where v.postid = p.id
        and v.votetypeid in (2,3)
    ) as total_votes,
    (
      select count(*)
      from postlinks pl
      where pl.postid = p.id and pl.linktypeid = 3
    ) as dup_links_out,
    (
      select count(*)
      from postlinks pl
      where pl.relatedpostid = p.id and pl.linktypeid = 3
    ) as dup_links_in
  from posts p
),
-- per-tag aggregated performance for recent questions
tag_perf as (
  select
    t.tagname,
    count(*) as q_count,
    avg(p.score)::float as avg_score,
    avg(coalesce(p.viewcount,0))::float as avg_views,
    avg(coalesce(p.answercount,0))::float as avg_answers,
    sum(case when pe.edited_early then 1 else 0 end)::float / nullif(count(*),0) as pct_edited_early
  from posts p
  join lateral (
    select unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
  ) t on p.posttypeid = 1 and p.creationdate >= (select since_date from params)
  left join post_engagement pe on pe.post_id = p.id
  group by t.tagname
),
-- select top-performing tags by combined score and views
top_tags as (
  select tp.*,
         row_number() over (order by (coalesce(tp.avg_score,0) * 1.0) + (coalesce(tp.avg_views,0) / 1000.0) desc) as rn
  from tag_perf tp
  where tp.q_count >= 5
),
-- assemble questions in top tags with user deciles and engagement
candidate_questions as (
  select
    p.id as question_id,
    p.title,
    p.creationdate,
    pe.score,
    pe.viewcount,
    pe.answercount,
    pe.total_votes,
    pe.dup_links_out,
    pe.dup_links_in,
    pe.edited_early,
    ua.user_id,
    ua.displayname,
    ur.rep_decile,
    tt.tagname,
    tt.avg_score as tag_avg_score,
    tt.avg_views as tag_avg_views
  from posts p
  join post_engagement pe on pe.post_id = p.id and p.posttypeid = 1
  join lateral (
    select unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
  ) t on true
  join top_tags tt on tt.tagname = t.tagname and tt.rn <= greatest(10, (select ceil(count(*) * (select top_fraction from params)) from top_tags))
  left join users u on u.id = p.owneruserid
  left join user_ranks ur on ur.user_id = u.id
  left join user_activity ua on ua.user_id = u.id
),
-- compute answer response times and quality via window functions
answer_metrics as (
  select
    a.parentid as question_id,
    count(*) as answers_count,
    min(a.creationdate) - q.creationdate as time_to_first_answer,
    avg(a.score)::float as avg_answer_score,
    max(a.score) as max_answer_score,
    count(*) filter (where a.id = q.acceptedanswerid) as accepted_present
  from posts a
  join posts q on q.id = a.parentid
  where a.posttypeid = 2
    and q.id in (select question_id from candidate_questions)
  group by a.parentid, q.creationdate, q.acceptedanswerid
),
-- identify duplicates and closures with reasons
question_flags as (
  select
    q.id as question_id,
    bool_or(pl.linktypeid = 3) as has_dup_link,
    max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as close_reason_id,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events
  from posts q
  left join postlinks pl on pl.postid = q.id
  left join posthistory ph on ph.postid = q.id and ph.posthistorytypeid in (10)
  where q.id in (select question_id from candidate_questions)
  group by q.id
),
-- synthesize a composite performance score
scored as (
  select
    cq.question_id,
    cq.title,
    cq.creationdate,
    cq.score,
    cq.viewcount,
    cq.answercount,
    cq.total_votes,
    cq.dup_links_out,
    cq.dup_links_in,
    cq.edited_early,
    cq.displayname,
    cq.rep_decile,
    cq.tagname,
    am.answers_count,
    am.time_to_first_answer,
    am.avg_answer_score,
    am.max_answer_score,
    qf.has_dup_link,
    qf.close_reason_id,
    qf.close_events,
    -- composite score: views weighted, score, answers, penalties for dups/closures
    (
      coalesce(cq.viewcount,0) / 500.0
      + coalesce(cq.score,0) * 1.5
      + coalesce(am.avg_answer_score,0)
      + coalesce(am.answers_count,0) * 0.5
      + case when cq.edited_early then 0.5 else 0 end
      - coalesce(cq.dup_links_in,0) * 2.0
      - case when qf.has_dup_link then 3.0 else 0.0 end
      - coalesce(qf.close_events,0) * 1.0
    ) as perf_score,
    -- time penalty/bonus normalized (earlier answers better)
    case
      when am.time_to_first_answer is null then 0.0
      when am.time_to_first_answer <= interval '1 hour' then 1.0
      when am.time_to_first_answer <= interval '1 day' then 0.5
      when am.time_to_first_answer <= interval '7 days' then 0.2
      else -0.2
    end as response_bonus
  from candidate_questions cq
  left join answer_metrics am on am.question_id = cq.question_id
  left join question_flags qf on qf.question_id = cq.question_id
),
-- rank within each tag and globally
ranked as (
  select
    s.*,
    (s.perf_score + s.response_bonus) as final_score,
    row_number() over (order by (s.perf_score + s.response_bonus) desc) as global_rank,
    row_number() over (partition by s.tagname order by (s.perf_score + s.response_bonus) desc) as tag_rank,
    dense_rank() over (order by coalesce(s.rep_decile, 10), (s.perf_score + s.response_bonus) desc) as decile_rank
  from scored s
),
-- include null/unknown tag close reasons mapping via left join
close_reasons as (
  select
    crt.id as close_reason_id,
    crt.name as close_reason_name
  from closereasontypes crt
)
select
  r.global_rank,
  r.tag_rank,
  r.decile_rank,
  r.final_score,
  r.question_id,
  coalesce(nullif(trim(regexp_replace(r.title, '\s+', ' ', 'g')), ''), '[no title]') as normalized_title,
  r.tagname as tag,
  r.displayname as owner_displayname,
  r.rep_decile,
  r.score,
  r.viewcount,
  r.answercount,
  r.total_votes,
  r.edited_early,
  r.has_dup_link,
  r.dup_links_in,
  r.dup_links_out,
  r.close_events,
  coalesce(cr.close_reason_name, 'Unknown/Not Closed') as close_reason_name,
  r.time_to_first_answer,
  r.avg_answer_score,
  r.max_answer_score,
  -- string expression combining summary
  (
    'Tag=' || r.tagname
    || '; Owner=' || coalesce(r.displayname, 'Anonymous')
    || '; RepDecile=' || coalesce(r.rep_decile::text, 'N/A')
    || '; Views=' || coalesce(r.viewcount::text, '0')
    || '; Score=' || coalesce(r.score::text, '0')
  ) as summary
from ranked r
left join close_reasons cr on cr.close_reason_id = r.close_reason_id
where r.tag_rank <= 5
   or r.global_rank <= 50
order by r.global_rank nulls last, r.tagname, r.tag_rank;