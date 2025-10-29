-- {"query": "355.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3465} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as normalized_location,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    max(b.date) as last_badge_date,
    row_number() over (partition by coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') order by u.reputation desc, u.id) as rn_loc
  from users u
  left join badges b
    on b.userid = u.id
   and b.date >= now() - interval '5 years'
  where u.creationdate >= now() - interval '10 years'
  group by u.id, u.displayname, u.reputation, u.creationdate, coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown')
),
posts_expanded as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.parentid,
    p.lastactivitydate,
    p.commentcount,
    p.favoritecount,
    array_length(string_to_array(coalesce(nullif(substring(p.tags, 2, greatest(length(p.tags)-2,0)), ''), ''), '><'), 1) as tag_count,
    case when p.posttypeid = 1 then 1 else 0 end as is_question,
    case when p.posttypeid = 2 then 1 else 0 end as is_answer
  from posts p
  where p.creationdate >= now() - interval '10 years'
),
question_metrics as (
  select
    q.owneruserid as user_id,
    count(*) as q_count,
    avg(q.score) as avg_q_score,
    percentile_cont(0.5) within group (order by q.score) as med_q_score,
    sum(coalesce(q.viewcount,0)) as total_q_views,
    sum(case when q.acceptedanswerid is not null then 1 else 0 end) as q_with_accept,
    avg(nullif(q.answercount,0)) as avg_answers_nonzero,
    avg(case when q.answercount is null or q.answercount = 0 then null else q.answercount::numeric end) as avg_answers_nonzero_explicit
  from posts_expanded q
  where q.posttypeid = 1
  group by q.owneruserid
),
answer_metrics as (
  select
    a.owneruserid as user_id,
    count(*) as a_count,
    avg(a.score) as avg_a_score,
    sum(case when a.score > 0 then 1 else 0 end)::numeric / nullif(count(*),0) as pct_pos_answers
  from posts_expanded a
  where a.posttypeid = 2
  group by a.owneruserid
),
commenters as (
  select
    c.userid as user_id,
    count(*) as c_count,
    avg(coalesce(c.score,0)) as avg_c_score,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.creationdate >= now() - interval '10 years'
  group by c.userid
),
postlinks_dupes as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as dup_count,
    count(*) filter (where pl.linktypeid = 1) as linked_count,
    max(pl.creationdate) as last_link_date
  from postlinks pl
  group by pl.postid
),
close_events as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid = 10) as close_votes,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_votes,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11)) as last_close_or_reopen,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 50) as last_comm_bump
  from posthistory ph
  where ph.posthistorytypeid in (10,11,50)
  group by ph.postid
),
user_post_agg as (
  select
    pe.owneruserid as user_id,
    count(*) as total_posts,
    sum(pe.is_question) as total_questions,
    sum(pe.is_answer) as total_answers,
    avg(pe.score) as avg_post_score,
    avg(coalesce(pe.viewcount,0)) as avg_views,
    avg(pe.tag_count) filter (where pe.posttypeid = 1) as avg_tags_per_question,
    max(pe.lastactivitydate) as last_activity,
    sum(case when coalesce(pe.title,'') ilike any (array['%help%','%urgent%','%plz%']) then 1 else 0 end) as flagged_titles
  from posts_expanded pe
  group by pe.owneruserid
),
question_quality as (
  select
    q.id as question_id,
    q.owneruserid as user_id,
    coalesce(qm.close_votes,0) as close_votes,
    coalesce(pl.dup_count,0) as dupes,
    coalesce(pl.linked_count,0) as linked,
    case
      when q.viewcount is null or q.viewcount = 0 then null
      else round( (q.score::numeric / nullif(q.viewcount,0)) * ln(1 + least(q.viewcount,10000)) , 6)
    end as score_view_norm,
    case when position('how to' in lower(coalesce(q.title,''))) > 0 then 1 else 0 end as is_howto,
    (select count(*) from comments c where c.postid = q.id and c.score > 0) as pos_comment_count
  from posts_expanded q
  left join postlinks_dupes pl on pl.postid = q.id
  left join close_events qm on qm.postid = q.id
  where q.posttypeid = 1
),
user_quality_rollup as (
  select
    qq.user_id,
    avg(qq.score_view_norm) as avg_q_score_norm,
    sum(qq.is_howto) as howto_count,
    sum(qq.dupes) as total_dupes,
    sum(qq.close_votes) as total_close_votes,
    sum(qq.pos_comment_count) as total_positive_comments_on_questions
  from question_quality qq
  group by qq.user_id
),
votes_agg as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounties,
    sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
  from votes v
  where v.creationdate >= now() - interval '10 years'
  group by v.userid
),
tag_influence as (
  select
    q.owneruserid as user_id,
    t.tagname,
    count(*) as tag_q_count,
    avg(q.score) as tag_avg_q_score,
    row_number() over (partition by q.owneruserid order by count(*) desc, avg(q.score) desc, t.tagname) as rn_tag
  from posts_expanded q
  join lateral unnest(string_to_array(coalesce(nullif(substring(q.tags, 2, greatest(length(q.tags)-2,0)), ''), ''), '><')) as tagname on true
  join tags t on t.tagname = tagname
  where q.posttypeid = 1
  group by q.owneruserid, t.tagname
),
top_tag as (
  select user_id,
         max(case when rn_tag = 1 then tagname end) as top_tag_name,
         max(case when rn_tag = 1 then tag_q_count end) as top_tag_qs,
         max(case when rn_tag = 1 then tag_avg_q_score end) as top_tag_avg_score
  from tag_influence
  group by user_id
),
users_baseline as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.normalized_location,
    ru.gold_count,
    ru.silver_count,
    ru.bronze_count,
    ru.last_badge_date
  from recent_users ru
  where ru.rn_loc <= 500
),
merged as (
  select
    ub.user_id,
    ub.displayname,
    ub.reputation,
    ub.creationdate,
    ub.normalized_location,
    coalesce(ub.gold_count,0) as gold_count,
    coalesce(ub.silver_count,0) as silver_count,
    coalesce(ub.bronze_count,0) as bronze_count,
    ub.last_badge_date,
    coalesce(up.total_posts,0) as total_posts,
    coalesce(up.total_questions,0) as total_questions,
    coalesce(up.total_answers,0) as total_answers,
    up.last_activity,
    coalesce(up.avg_post_score,0) as avg_post_score,
    coalesce(up.avg_views,0) as avg_views,
    up.avg_tags_per_question,
    up.flagged_titles,
    qm.q_count,
    qm.avg_q_score,
    qm.med_q_score,
    qm.total_q_views,
    qm.q_with_accept,
    coalesce(am.a_count,0) as a_count,
    am.avg_a_score,
    am.pct_pos_answers,
    uqr.avg_q_score_norm,
    uqr.howto_count,
    uqr.total_dupes,
    uqr.total_close_votes,
    uqr.total_positive_comments_on_questions,
    coalesce(va.upvotes_cast,0) as upvotes_cast,
    coalesce(va.downvotes_cast,0) as downvotes_cast,
    coalesce(va.bounties,0) as bounties,
    coalesce(va.bounty_total,0) as bounty_total,
    tt.top_tag_name,
    tt.top_tag_qs,
    tt.top_tag_avg_score
  from users_baseline ub
  left join user_post_agg up on up.user_id = ub.user_id
  left join question_metrics qm on qm.user_id = ub.user_id
  left join answer_metrics am on am.user_id = ub.user_id
  left join user_quality_rollup uqr on uqr.user_id = ub.user_id
  left join votes_agg va on va.user_id = ub.user_id
  left join top_tag tt on tt.user_id = ub.user_id
),
ranked as (
  select
    m.*,
    coalesce(m.avg_q_score_norm, 0) as avg_q_score_norm_nz,
    coalesce(m.avg_tags_per_question, 0) as avg_tags_per_question_nz,
    coalesce(m.avg_a_score, 0) as avg_a_score_nz,
    coalesce(m.pct_pos_answers, 0) as pct_pos_answers_nz,
    dense_rank() over (order by m.reputation desc, coalesce(m.total_posts,0) desc, coalesce(m.avg_post_score,0) desc) as dr_global,
    row_number() over (partition by m.normalized_location order by m.reputation desc, coalesce(m.total_posts,0) desc, m.user_id) as rn_by_location,
    row_number() over (order by
      -- composite score emphasizing reputation, question quality, acceptance, and participation
      (m.reputation::numeric
       + coalesce(m.q_with_accept,0) * 15
       + coalesce(m.avg_q_score_norm,0) * 100
       + coalesce(m.a_count,0) * 2
       + greatest(coalesce(m.upvotes_cast,0) - coalesce(m.downvotes_cast,0), 0) * 0.5
       + coalesce(m.gold_count,0) * 25 + coalesce(m.silver_count,0) * 10 + coalesce(m.bronze_count,0) * 3
       - coalesce(m.total_dupes,0) * 5
       - coalesce(m.total_close_votes,0) * 2)::numeric desc,
      m.user_id) as rn_composite
  from merged m
),
bench as (
  select
    r.*,
    -- string expressions with null logic
    trim(both ' ' from coalesce(r.displayname, 'user_' || r.user_id::text)) as safe_displayname,
    case
      when r.top_tag_name is not null then r.top_tag_name || ' (' || coalesce(r.top_tag_qs::text, '0') || ')'
      else 'n/a'
    end as top_tag_summary,
    -- complicated predicate flags
    case
      when coalesce(r.avg_q_score_norm_nz,0) > 0.02 and coalesce(r.avg_a_score_nz,0) > 1 then 'Elite'
      when coalesce(r.avg_q_score_norm_nz,0) > 0.01 and r.q_with_accept >= 5 then 'Strong'
      when coalesce(r.total_posts,0) >= 50 and coalesce(r.avg_post_score,0) >= 1 then 'Active'
      else 'Rising'
    end as cohort,
    case
      when r.last_activity is null then 'Dormant'
      when r.last_activity >= now() - interval '90 days' then 'Hot'
      when r.last_activity >= now() - interval '365 days' then 'Warm'
      else 'Cool'
    end as activity_band
  from ranked r
)
select
  b.user_id,
  b.safe_displayname,
  b.normalized_location,
  b.reputation,
  b.gold_count,
  b.silver_count,
  b.bronze_count,
  b.total_posts,
  b.total_questions,
  b.total_answers,
  round(coalesce(b.avg_post_score,0)::numeric, 3) as avg_post_score,
  round(coalesce(b.avg_q_score,0)::numeric, 3) as avg_q_score,
  round(coalesce(b.med_q_score,0)::numeric, 3) as med_q_score,
  round(coalesce(b.avg_q_score_norm_nz,0)::numeric, 6) as avg_q_score_norm,
  round(coalesce(b.avg_a_score_nz,0)::numeric, 3) as avg_a_score,
  round(coalesce(b.pct_pos_answers_nz,0)::numeric, 3) as pct_pos_answers,
  b.q_with_accept,
  b.total_q_views,
  b.total_dupes,
  b.total_close_votes,
  b.total_positive_comments_on_questions,
  b.upvotes_cast,
  b.downvotes_cast,
  b.bounties,
  b.bounty_total,
  b.top_tag_summary,
  b.cohort,
  b.activity_band,
  b.dr_global,
  b.rn_by_location,
  b.rn_composite
from bench b
where
  -- complex predicate combining null logic, string search, and metrics
  (
    b.reputation >= 1000
    or (b.total_posts >= 25 and coalesce(b.avg_post_score,0) >= 0.5)
    or (b.avg_q_score_norm_nz > 0.005 and coalesce(b.top_tag_name,'') <> '')
  )
  and not (b.total_dupes is not null and b.total_dupes > 500)
  and (
    position('test' in lower(b.safe_displayname)) = 0
    or b.gold_count >= 1
  )
  and case when b.normalized_location ilike any (array['%antarctica%','%moon%']) then false else true end
order by
  b.rn_composite,
  b.dr_global,
  b.user_id
limit 1000;