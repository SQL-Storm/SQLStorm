-- {"query": "443.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3185} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(nullif(trim(u.location), ''), '(unknown)') as location_norm,
         date_trunc('month', u.creationdate) as signup_month
  from users u
  where u.creationdate >= (select max(p.creationdate) from posts p) - interval '3 years'
),
questions as (
  select p.id,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.closeddate
  from posts p
  where p.posttypeid = 1
),
answers as (
  select a.id,
         a.parentid as question_id,
         a.owneruserid as owner_user_id,
         a.creationdate,
         a.score
  from posts a
  where a.posttypeid = 2
),
q_activity as (
  select q.id as question_id,
         q.owneruserid as asker_id,
         q.creationdate as q_created,
         q.score as q_score,
         q.viewcount as q_views,
         q.acceptedanswerid,
         q.closeddate,
         count(distinct a.id) as answer_count,
         count(distinct c.id) as comment_count,
         max(coalesce(a.creationdate, c.creationdate, q.creationdate)) as last_activity,
         min(a.creationdate) filter (where a.id is not null) as first_answer_at,
         percentile_cont(0.5) within group (order by a.creationdate) filter (where a.id is not null) as median_answer_time,
         sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
         sum(case when a.score < 0 then 1 else 0 end) as negative_answers
  from questions q
  left join answers a on a.question_id = q.id
  left join comments c on c.postid = q.id
  group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.acceptedanswerid, q.closeddate
),
tags_expanded as (
  select q.id as question_id,
         unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  from questions q
  where q.tags is not null and length(q.tags) > 2
),
tag_weight as (
  select te.tagname,
         sum(qa.q_views) as total_views,
         count(*) as q_cnt,
         avg(qa.q_score) as avg_q_score
  from tags_expanded te
  join q_activity qa on qa.question_id = te.question_id
  group by te.tagname
),
q_votes as (
  select v.postid as question_id,
         sum(case when vt.name = 'UpMod' then 1 else 0 end) as upvotes,
         sum(case when vt.name = 'DownMod' then 1 else 0 end) as downvotes,
         sum(case when vt.name = 'Favorite' then 1 else 0 end) as favorites
  from votes v
  join votetypes vt on vt.id = v.votetypeid
  join questions q on q.id = v.postid
  group by v.postid
),
closures as (
  select ph.postid as question_id,
         min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
         max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id
  from posthistory ph
  join questions q on q.id = ph.postid
  group by ph.postid
),
dupes as (
  select pl.postid as question_id,
         count(*) filter (where pl.linktypeid = 3) as duplicate_links,
         count(*) filter (where pl.linktypeid = 1) as related_links
  from postlinks pl
  join questions q on q.id = pl.postid
  group by pl.postid
),
user_badges as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold,
         sum(case when b.class = 2 then 1 else 0 end) as silver,
         sum(case when b.class = 3 then 1 else 0 end) as bronze,
         count(*) as total_badges,
         max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
answerer_stats as (
  select a.owner_user_id as user_id,
         count(*) as answers_written,
         avg(a.score) as avg_answer_score,
         sum(case when a.score > 0 then 1 else 0 end) as pos_answers,
         sum(case when a.score < 0 then 1 else 0 end) as neg_answers,
         min(a.creationdate) as first_answer_at,
         max(a.creationdate) as last_answer_at
  from answers a
  group by a.owner_user_id
),
asker_stats as (
  select q.owneruserid as user_id,
         count(*) as questions_asked,
         avg(q.score) as avg_q_score,
         avg(q.viewcount) as avg_q_views,
         sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_count
  from questions q
  group by q.owneruserid
),
user_rollup as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         coalesce(ub.total_badges, 0) as total_badges,
         coalesce(ub.gold, 0) as gold,
         coalesce(ub.silver, 0) as silver,
         coalesce(ub.bronze, 0) as bronze,
         coalesce(asr.answers_written, 0) as answers_written,
         coalesce(ask.questions_asked, 0) as questions_asked,
         coalesce(asr.avg_answer_score, 0) as avg_answer_score,
         coalesce(ask.avg_q_score, 0) as avg_q_score,
         coalesce(ask.avg_q_views, 0) as avg_q_views,
         coalesce(ask.accepted_count, 0) as accepted_questions,
         u.creationdate,
         u.lastaccessdate
  from users u
  left join user_badges ub on ub.userid = u.id
  left join answerer_stats asr on asr.user_id = u.id
  left join asker_stats ask on ask.user_id = u.id
),
q_enriched as (
  select qa.question_id,
         qa.asker_id,
         qa.q_created,
         qa.q_score,
         qa.q_views,
         qa.answer_count,
         qa.comment_count,
         qa.last_activity,
         qa.first_answer_at,
         qa.median_answer_time,
         qa.positive_answers,
         qa.negative_answers,
         coalesce(qv.upvotes, 0) as upvotes,
         coalesce(qv.downvotes, 0) as downvotes,
         coalesce(qv.favorites, 0) as favorites,
         coalesce(d.duplicate_links, 0) as duplicate_links,
         coalesce(d.related_links, 0) as related_links,
         c.first_closed_at,
         c.last_reopened_at,
         c.last_close_reason_id,
         case
           when qa.closeddate is not null then 'Closed'
           when qa.acceptedanswerid is not null then 'Answered'
           when qa.answer_count = 0 and now() - qa.q_created > interval '90 days' then 'Stale'
           else 'Open'
         end as q_status
  from q_activity qa
  left join q_votes qv on qv.question_id = qa.question_id
  left join dupes d on d.question_id = qa.question_id
  left join closures c on c.question_id = qa.question_id
),
tag_rank as (
  select tw.tagname,
         tw.q_cnt,
         tw.total_views,
         dense_rank() over (order by tw.q_cnt desc, tw.total_views desc) as popularity_rank
  from tag_weight tw
),
answer_firsts as (
  select question_id,
         owner_user_id as first_answerer_id,
         creationdate as first_answer_time,
         row_number() over (partition by question_id order by creationdate asc, id asc) as rn
  from answers
),
accepted_answerers as (
  select q.id as question_id,
         p.owneruserid as accepted_owner_id
  from questions q
  join posts p on p.id = q.acceptedanswerid
),
question_scores as (
  select qe.*,
         coalesce(af.first_answerer_id, -1) as first_answerer_id,
         coalesce(aa.accepted_owner_id, -1) as accepted_answerer_id,
         case when aa.accepted_owner_id is not null and af.first_answerer_id = aa.accepted_owner_id then 1 else 0 end as first_equals_accepted
  from q_enriched qe
  left join answer_firsts af on af.question_id = qe.question_id and af.rn = 1
  left join accepted_answerers aa on aa.question_id = qe.question_id
),
per_user_metrics as (
  select
    qr.user_id,
    count(*) filter (where qs.asker_id = qr.user_id) as questions_asked_recent,
    avg(qs.q_score) filter (where qs.asker_id = qr.user_id) as avg_q_score_recent,
    avg(extract(epoch from (qs.first_answer_at - qs.q_created))/3600.0) filter (where qs.asker_id = qr.user_id and qs.first_answer_at is not null) as avg_hours_to_first_answer,
    sum(case when qs.first_equals_accepted = 1 then 1 else 0 end) filter (where qs.asker_id = qr.user_id) as times_first_equals_accepted,
    count(*) filter (where qs.accepted_answerer_id = qr.user_id) as accepted_answers_given,
    avg(qs.q_views) filter (where qs.asker_id = qr.user_id) as avg_views_on_asked,
    sum(qs.duplicate_links) filter (where qs.asker_id = qr.user_id) as dupes_on_asked
  from recent_users qr
  left join question_scores qs on qs.asker_id = qr.user_id or qs.accepted_answerer_id = qr.user_id
  group by qr.user_id
),
final_scores as (
  select
    ur.user_id,
    ur.displayname,
    ur.reputation,
    ur.total_badges,
    ur.gold, ur.silver, ur.bronze,
    ur.answers_written,
    ur.questions_asked,
    ur.avg_answer_score,
    ur.avg_q_score,
    ur.avg_q_views,
    ur.accepted_questions,
    pur.questions_asked_recent,
    pur.accepted_answers_given,
    coalesce(pur.avg_hours_to_first_answer, 9999) as avg_hours_to_first_answer,
    coalesce(pur.avg_q_score_recent, 0) as avg_q_score_recent,
    coalesce(pur.avg_views_on_asked, 0) as avg_views_on_asked,
    coalesce(pur.dupes_on_asked, 0) as dupes_on_asked,
    coalesce(pur.times_first_equals_accepted, 0) as times_first_equals_accepted,
    -- composite score mixing log scales and z-ish normalizations
    (
      log(1 + greatest(ur.reputation,0))
      + 0.5 * log(1 + ur.total_badges)
      + 0.3 * coalesce(ur.avg_answer_score, 0)
      + 0.2 * coalesce(ur.avg_q_score, 0)
      + 0.001 * coalesce(ur.avg_q_views, 0)
      + 0.4 * coalesce(pur.accepted_answers_given, 0)
      - 0.05 * coalesce(pur.dupes_on_asked, 0)
      - 0.02 * coalesce(ur.downvotes, 0) -- may be null; keep as placeholder
    ) as composite_activity_score
  from user_rollup ur
  left join per_user_metrics pur on pur.user_id = ur.user_id
),
top_tags_per_user as (
  select
    qs.asker_id as user_id,
    te.tagname,
    count(*) as tag_q_count,
    row_number() over (partition by qs.asker_id order by count(*) desc, te.tagname asc) as rn
  from question_scores qs
  join tags_expanded te on te.question_id = qs.question_id
  group by qs.asker_id, te.tagname
),
user_top3_tags as (
  select user_id,
         string_agg(tagname || ' (' || tag_q_count::text || ')', ', ' order by rn) as top3_tags
  from top_tags_per_user
  where rn <= 3
  group by user_id
)
select
  fs.user_id,
  ru.displayname,
  ru.location_norm,
  ru.signup_month,
  fs.reputation,
  fs.total_badges,
  fs.gold, fs.silver, fs.bronze,
  fs.answers_written,
  fs.questions_asked,
  fs.accepted_questions,
  fs.accepted_answers_given,
  round(fs.avg_answer_score::numeric, 2) as avg_answer_score,
  round(fs.avg_q_score::numeric, 2) as avg_q_score,
  round(fs.avg_q_views::numeric, 2) as avg_q_views,
  round(fs.avg_q_score_recent::numeric, 2) as avg_q_score_recent,
  round(fs.avg_hours_to_first_answer::numeric, 2) as avg_hours_to_first_answer,
  round(fs.avg_views_on_asked::numeric, 2) as avg_views_on_asked,
  fs.dupes_on_asked,
  fs.times_first_equals_accepted,
  round(fs.composite_activity_score::numeric, 3) as composite_activity_score,
  coalesce(utt.top3_tags, '(none)') as top3_tags,
  case
    when fs.reputation >= 100000 then 'Legend'
    when fs.reputation >= 50000 then 'Elite'
    when fs.reputation >= 10000 then 'Veteran'
    when fs.reputation >= 1000 then 'Regular'
    else 'Newbie'
  end as user_band
from final_scores fs
join recent_users ru on ru.user_id = fs.user_id
left join user_top3_tags utt on utt.user_id = fs.user_id
where coalesce(fs.answers_written, 0) + coalesce(fs.questions_asked, 0) > 0
order by fs.composite_activity_score desc nulls last, fs.reputation desc, fs.user_id
limit 200;