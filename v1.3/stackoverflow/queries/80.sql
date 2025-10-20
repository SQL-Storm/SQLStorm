with
-- user reputation deciles and activity summary
user_activity as (
  select
    u.id,
    u.reputation,
    rank() over (order by u.reputation desc) as rep_rank,
    ntile(10) over (order by u.reputation desc) as rep_decile,
    count(p.id) filter (where p.posttypeid = 1) as questions_posted,
    count(p.id) filter (where p.posttypeid = 2) as answers_posted,
    max(p.creationdate) as last_post_date,
    coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end),0) as net_votes_on_posts
  from users u
  left join posts p on p.owneruserid = u.id
  left join votes v on v.postid = p.id
  group by u.id, u.reputation
),
-- heavy questions with tag parsing, tag count, complexity score
question_tags as (
  select
    q.id as question_id,
    q.title,
    q.owneruserid,
    q.creationdate,
    q.score,
    q.viewcount,
    q.answercount,
    coalesce(array_length(string_to_array(substring(q.tags from 2 for (length(q.tags) - 2)), '><'),1),0) as tag_count,
    -- normalized tag string for pattern checks (lowercase)
    lower(coalesce(q.tags,'')) as raw_tags,
    -- heuristic complexity: weighted combination of text length, answers, views, score
    (length(coalesce(q.body,'')) / 200.0
     + coalesce(q.answercount,0) * 2.0
     + coalesce(q.viewcount,0) / greatest(1.0, nullif(q.answercount,0) + 10)
     + coalesce(q.score,0) * 1.5) as complexity_score
  from posts q
  where q.posttypeid = 1
),
-- top answers per question with correlated subquery and windowed ranking
top_answers as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid,
    a.creationdate,
    a.score,
    a.body,
    a.lastactivitydate,
    row_number() over (partition by a.parentid order by a.score desc, a.creationdate asc) as answer_rank,
    -- jittered score for benchmark testing: score + sin(id)
    a.score + sin(cast(a.id as double precision)) as jittered_score
  from posts a
  where a.posttypeid = 2
),
-- compute per-question aggregates joining questions and answers
question_stats as (
  select
    qt.question_id,
    qt.title,
    qt.owneruserid,
    qt.creationdate,
    qt.score as question_score,
    qt.viewcount,
    qt.answercount,
    qt.tag_count,
    qt.raw_tags,
    qt.complexity_score,
    -- aggregated stats about answers with null-safe logic
    (select count(*) from posts aa where aa.posttypeid = 2 and aa.parentid = qt.question_id) as answers_total,
    (select count(*) filter (where v.votetypeid = 2) from posts aa left join votes v on v.postid = aa.id where aa.posttypeid = 2 and aa.parentid = qt.question_id) as answers_upvotes,
    (select max(a.score) from posts a where a.posttypeid = 2 and a.parentid = qt.question_id) as top_answer_score,
    -- correlated: accepted answer age in seconds (if exists)
    (select extract(epoch from (a.creationdate - qt.creationdate)) from posts a where a.id = (select p.acceptedanswerid from posts p where p.id = qt.question_id) limit 1) as accepted_answer_age_seconds
  from question_tags qt
),
-- link graph metrics (in-degree/out-degree) and duplicate relationships
post_link_metrics as (
  select
    p.id,
    p.posttypeid,
    coalesce(pl_out.out_degree,0) as out_degree,
    coalesce(pl_in.in_degree,0) as in_degree,
    coalesce(sum(case when pl_out.linktypeid = 3 then 1 else 0 end),0) as duplicates_declared,
    exists (
      select 1 from postlinks l where l.postid = p.id and l.linktypeid = 3
    ) as has_duplicate_flag
  from posts p
  left join (
    select postid, count(*) as out_degree, max(linktypeid) as linktypeid
    from postlinks
    group by postid
  ) pl_out on pl_out.postid = p.id
  left join (
    select relatedpostid as postid, count(*) as in_degree
    from postlinks
    group by relatedpostid
  ) pl_in on pl_in.postid = p.id
  group by p.id, p.posttypeid, pl_out.out_degree, pl_in.in_degree, pl_out.linktypeid
),
-- compute user neighborhood score combining badges, votes, and links
user_social as (
  select
    u.id as user_id,
    coalesce(b.badge_count,0) as badges_awarded,
    coalesce(vt.upvotes_received,0) as upvotes_received,
    coalesce(avg_q.comp_score,0) as avg_question_complexity,
    coalesce(sum(plm.out_degree),0) as total_out_links_from_posts,
    -- social index: weighted sum with null protections
    (coalesce(b.badge_count,0) * 1.2 + coalesce(vt.upvotes_received,0) * 0.8 + coalesce(avg_q.comp_score,0) * 0.5 + coalesce(sum(plm.out_degree),0) * 0.3) as social_index
  from users u
  left join (
    select userid, count(*) as badge_count from badges group by userid
  ) b on b.userid = u.id
  left join (
    select p.owneruserid as userid, count(v.id) filter (where v.votetypeid = 2) as upvotes_received
    from posts p
    left join votes v on v.postid = p.id
    group by p.owneruserid
  ) vt on vt.userid = u.id
  left join (
    select owneruserid, avg((length(coalesce(body,''))/200.0 + coalesce(answercount,0)*2.0 + coalesce(viewcount,0)/10.0)) as comp_score
    from posts
    where posttypeid = 1
    group by owneruserid
  ) avg_q on avg_q.owneruserid = u.id
  left join posts p on p.owneruserid = u.id
  left join post_link_metrics plm on plm.id = p.id
  group by u.id, b.badge_count, vt.upvotes_received, avg_q.comp_score
),
-- final ranking of interesting questions with many constructs
ranked_questions as (
  select
    qs.question_id,
    qs.title,
    qs.owneruserid,
    coalesce(u.displayname, '<<deleted>>') as owner_display,
    qs.creationdate,
    qs.question_score,
    qs.viewcount,
    qs.answercount,
    qs.tag_count,
    qs.raw_tags,
    qs.complexity_score,
    qs.answers_total,
    qs.answers_upvotes,
    qs.top_answer_score,
    qs.accepted_answer_age_seconds,
    coalesce(pl.out_degree,0) as link_out,
    coalesce(pl.in_degree,0) as link_in,
    us.social_index,
    ua.rep_decile,
    -- fancy score: complexity * log(view+1) + normalized social influence + inverse of accepted answer latency
    (qs.complexity_score * ln(greatest(qs.viewcount,1) + 1)
     + coalesce(us.social_index,0) / nullif(1 + ua.rep_decile,0)
     - coalesce(qs.accepted_answer_age_seconds, 0) / greatest(1, extract(epoch from (timestamp '2024-10-01 12:34:56' - qs.creationdate))/86400 + 1)
    ) as interest_score,
    -- tag locality: whether contains 'sql' or popular tags via set operator check
    (case when qs.raw_tags like '%<sql>%' then 1 else 0 end) as has_sql_tag,
    (case when qs.raw_tags ~ '<(java|python|c#|javascript)>' then 1 else 0 end) as has_popular_lang,
    us.social_index as social_index_out
  from question_stats qs
  left join post_link_metrics pl on pl.id = qs.question_id
  left join users u on u.id = qs.owneruserid
  left join user_social us on us.user_id = qs.owneruserid
  left join user_activity ua on ua.id = qs.owneruserid
)
select
  rq.question_id,
  rq.title,
  left(rq.owner_display, 30) as owner_snippet,
  rq.creationdate,
  rq.question_score,
  rq.viewcount,
  rq.answercount,
  rq.tag_count,
  rq.has_sql_tag,
  rq.has_popular_lang,
  round(cast(rq.complexity_score as numeric),2) as complexity_score,
  round(cast(rq.interest_score as numeric),4) as interest_score,
  rq.top_answer_score,
  case
    when rq.accepted_answer_age_seconds is null then 'no accepted answer'
    when rq.accepted_answer_age_seconds < 3600 then 'accepted_within_hour'
    when rq.accepted_answer_age_seconds < 86400 then 'accepted_within_day'
    else 'accepted_after_day'
  end as accepted_age_bucket,
  rq.social_index,
  rq.rep_decile
from ranked_questions rq
where
  (rq.interest_score > 50 or (rq.has_sql_tag = 1 and rq.complexity_score > 10))
  and rq.viewcount > 100
  and (rq.tag_count between 1 and 5)
  and not (rq.raw_tags is null)
order by rq.interest_score desc nulls last, rq.viewcount desc
limit 250;