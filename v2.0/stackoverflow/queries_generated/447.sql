-- {"query": "447.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3121} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    extract(year from age(current_timestamp, u.creationdate))::int as account_age_years,
    row_number() over (order by u.reputation desc, u.id) as rn_global
  from users u
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from users)
),
user_badge_stats as (
  select
    b.userid,
    count(*) as total_badges,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
posts_enriched as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    coalesce(p.viewcount, 0) as viewcount,
    coalesce(p.commentcount, 0) as commentcount,
    coalesce(p.favoritecount, 0) as favoritecount,
    nullif(trim(p.title), '') as title,
    p.tags,
    p.answercount,
    case when p.closeddate is not null then 1 else 0 end as is_closed,
    case when p.communityowneddate is not null then 1 else 0 end as is_community_owned,
    length(coalesce(p.body, '')) as body_len,
    substring(coalesce(p.title, ''), 1, 80) as title_sample
  from posts p
  where p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '5 years' from posts)
),
question_answers as (
  select
    q.id as question_id,
    q.owneruserid as question_ownerid,
    q.creationdate as question_created,
    q.score as question_score,
    q.viewcount,
    q.commentcount as question_commentcount,
    q.title,
    q.tags,
    q.answercount,
    q.is_closed,
    q.is_community_owned,
    q.body_len as question_body_len,
    count(a.id) as actual_answers,
    sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
    max(a.score) as max_answer_score,
    min(a.creationdate) as first_answer_date,
    max(a.creationdate) as last_answer_date
  from posts_enriched q
  left join posts_enriched a
    on a.parentid = q.id
   and a.posttypeid = 2
  where q.posttypeid = 1
  group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.commentcount, q.title, q.tags, q.answercount, q.is_closed, q.is_community_owned, q.body_len
),
vote_agg as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    count(*) filter (where v.votetypeid = 10) as deletions,
    count(*) filter (where v.votetypeid = 11) as undeletions,
    sum(coalesce(v.bountyamount, 0)) filter (where v.votetypeid in (8,9)) as bounty_total,
    count(distinct case when v.votetypeid in (8,9) then v.userid end) as bounty_users
  from votes v
  where v.creationdate >= (select date_trunc('year', max(creationdate)) - interval '5 years' from votes)
  group by v.postid
),
comments_agg as (
  select
    c.postid,
    count(*) as comments_total,
    sum(case when c.score > 0 then 1 else 0 end) as comments_positive,
    max(c.creationdate) as last_comment_date,
    string_agg(distinct coalesce(nullif(trim(c.userdisplayname), ''), 'anon'), ', ' order by coalesce(nullif(trim(c.userdisplayname), ''), 'anon') asc) as commenters_sample
  from comments c
  group by c.postid
),
question_close_reasons as (
  select
    ph.postid as question_id,
    max(ph.creationdate) as last_close_event,
    max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_code,
    max(case when ph.posthistorytypeid = 10 then ph.text end) as last_close_payload
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
duplicate_links as (
  select
    pl.postid as dupe_id,
    count(*) filter (where pl.linktypeid = 3) as duplicates_marked,
    count(*) filter (where pl.linktypeid = 1) as links_linked
  from postlinks pl
  group by pl.postid
),
tag_extracted as (
  select
    q.question_id,
    unnest(string_to_array(substring(coalesce(q.tags, ''), 2, nullif(length(coalesce(q.tags, '')),0)-2), '><')) as tag
  from question_answers q
),
tag_rank as (
  select
    te.tag,
    count(*) as tag_q_count,
    row_number() over (order by count(*) desc, tag) as tag_rank_overall
  from tag_extracted te
  group by te.tag
),
user_post_activity as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as questions_posted,
    count(*) filter (where p.posttypeid = 2) as answers_posted,
    sum(coalesce(p.score,0)) as total_post_score,
    max(p.lastactivitydate) as last_post_activity
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
q_metrics as (
  select
    qa.question_id,
    qa.question_ownerid,
    qa.question_created,
    qa.question_score,
    qa.viewcount,
    qa.question_commentcount,
    qa.title,
    qa.answercount,
    qa.actual_answers,
    qa.positive_answers,
    qa.max_answer_score,
    qa.first_answer_date,
    qa.last_answer_date,
    qa.is_closed,
    qa.is_community_owned,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.bounty_total,0) as bounty_total,
    coalesce(va.bounty_users,0) as bounty_users,
    coalesce(ca.comments_total,0) as comments_total,
    coalesce(ca.comments_positive,0) as comments_positive,
    ca.last_comment_date,
    coalesce(dl.duplicates_marked,0) as duplicates_marked,
    coalesce(dl.links_linked,0) as links_linked,
    qcr.last_close_event,
    qcr.last_close_code,
    qa.question_body_len
  from question_answers qa
  left join vote_agg va on va.postid = qa.question_id
  left join comments_agg ca on ca.postid = qa.question_id
  left join duplicate_links dl on dl.dupe_id = qa.question_id
  left join question_close_reasons qcr on qcr.question_id = qa.question_id
),
ranked_questions as (
  select
    qm.*,
    sum(qm.upvotes - qm.downvotes) over (order by qm.upvotes - qm.downvotes desc, qm.viewcount desc rows between unbounded preceding and current row) as running_net_votes,
    dense_rank() over (order by (qm.upvotes - qm.downvotes) desc) as d_rank_net_votes,
    row_number() over (partition by case when qm.is_closed = 1 then 'closed' else 'open' end order by qm.viewcount desc) as rn_by_closed_state,
    percentile_disc(0.9) within group (order by qm.viewcount) over () as p90_views_global
  from q_metrics qm
),
user_combined as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.account_age_years,
    ups.questions_posted,
    ups.answers_posted,
    ups.total_post_score,
    ups.last_post_activity,
    ubs.total_badges,
    ubs.gold_badges,
    ubs.silver_badges,
    ubs.bronze_badges,
    ubs.tag_badges
  from recent_users ru
  left join user_post_activity ups on ups.user_id = ru.user_id
  left join user_badge_stats ubs on ubs.userid = ru.user_id
),
question_tag_signature as (
  select
    te.question_id,
    string_agg(distinct tr.tag || ':' || tr.tag_rank_overall, ' | ' order by tr.tag_rank_overall asc) as tag_signature
  from tag_extracted te
  join tag_rank tr on tr.tag = te.tag
  group by te.question_id
),
final_scored as (
  select
    rq.question_id,
    rq.title,
    rq.question_ownerid,
    u.displayname as owner_displayname,
    coalesce(u.location, 'unknown') as owner_location,
    rq.viewcount,
    rq.upvotes,
    rq.downvotes,
    rq.bounty_total,
    rq.bounty_users,
    rq.comments_total,
    rq.duplicates_marked,
    rq.last_close_event,
    rq.last_close_code,
    rq.is_closed,
    rq.is_community_owned,
    rq.question_created,
    rq.first_answer_date,
    rq.last_answer_date,
    rq.actual_answers,
    rq.max_answer_score,
    rq.question_score,
    rq.running_net_votes,
    rq.d_rank_net_votes,
    rq.rn_by_closed_state,
    qt.tag_signature,
    coalesce(uc.total_badges,0) as owner_badges,
    coalesce(uc.gold_badges,0) as owner_gold,
    coalesce(uc.silver_badges,0) as owner_silver,
    coalesce(uc.bronze_badges,0) as owner_bronze,
    coalesce(uc.questions_posted,0) as owner_questions_posted,
    coalesce(uc.answers_posted,0) as owner_answers_posted,
    coalesce(uc.total_post_score,0) as owner_total_post_score,
    (
      (rq.viewcount::numeric / nullif(rq.p90_views_global::numeric,0)) * 0.25
      + (greatest(rq.upvotes - rq.downvotes, 0)::numeric) * 0.20
      + (coalesce(rq.bounty_total,0)::numeric / 100.0) * 0.10
      + (least(coalesce(rq.comments_total,0), 50)::numeric / 50.0) * 0.10
      + (coalesce(rq.actual_answers,0)::numeric / nullif(greatest(rq.answercount,1),0)) * 0.10
      + (least(coalesce(rq.max_answer_score,0), 20)::numeric / 20.0) * 0.10
      + (case when rq.is_closed = 1 then 0.0 else 0.05 end)
      + (case when rq.duplicates_marked > 0 then -0.05 else 0.0 end)
    ) as composite_score
  from ranked_questions rq
  left join users u on u.id = rq.question_ownerid
  left join user_combined uc on uc.user_id = rq.question_ownerid
  left join question_tag_signature qt on qt.question_id = rq.question_id
)
select
  fs.question_id,
  coalesce(nullif(fs.title, ''), concat('[untitled #', fs.question_id::varchar, ']')) as title,
  fs.owner_displayname,
  fs.owner_location,
  fs.tag_signature,
  fs.viewcount,
  fs.upvotes,
  fs.downvotes,
  fs.bounty_total,
  fs.bounty_users,
  fs.comments_total,
  fs.actual_answers,
  fs.max_answer_score,
  fs.question_score,
  fs.is_closed,
  fs.is_community_owned,
  fs.last_close_event,
  fs.last_close_code,
  to_char(fs.question_created, 'YYYY-MM-DD') as question_created,
  to_char(fs.first_answer_date, 'YYYY-MM-DD') as first_answer_date,
  to_char(fs.last_answer_date, 'YYYY-MM-DD') as last_answer_date,
  fs.owner_badges,
  fs.owner_gold,
  fs.owner_silver,
  fs.owner_bronze,
  fs.owner_questions_posted,
  fs.owner_answers_posted,
  fs.owner_total_post_score,
  fs.running_net_votes,
  fs.d_rank_net_votes,
  fs.rn_by_closed_state,
  round(fs.composite_score::numeric, 4) as composite_score,
  case
    when fs.composite_score >= percentile_disc(0.95) within group (order by fs.composite_score) over () then 'top-5%'
    when fs.composite_score >= percentile_disc(0.75) within group (order by fs.composite_score) over () then 'top-25%'
    when fs.composite_score >= percentile_disc(0.50) within group (order by fs.composite_score) over () then 'top-50%'
    else 'bottom-50%'
  end as score_bucket
from final_scored fs
where
  coalesce(fs.viewcount,0) > 0
  and (
    fs.composite_score > (
      select avg((upvotes - downvotes)::numeric) / nullif(avg(viewcount)::numeric,0)
      from ranked_questions
    )
    or fs.actual_answers >= all (
      select coalesce(actual_answers,0)
      from ranked_questions rq2
      where rq2.question_ownerid = fs.question_ownerid
        and rq2.question_id <> fs.question_id
    )
  )
order by fs.composite_score desc nulls last, fs.viewcount desc, fs.question_id
limit 500;