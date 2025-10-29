with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as website_normalized,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as questions,
    count(*) filter (where p.posttypeid = 2) as answers,
    sum(coalesce(p.score,0)) as post_score,
    sum(coalesce(p.viewcount,0)) as views,
    max(p.lastactivitydate) as last_post_activity,
    count(*) filter (where p.closeddate is not null) as closed_posts
  from posts p
  group by p.owneruserid
),
badge_rollup as (
  select
    b.userid as user_id,
    count(*) as total_badges,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
comment_stats as (
  select
    c.userid as user_id,
    count(*) as comments,
    sum(coalesce(c.score,0)) as comment_score,
    max(c.creationdate) as last_comment_date
  from comments c
  group by c.userid
),
vote_agg as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total_cast,
    max(v.creationdate) as last_vote_date
  from votes v
  group by v.userid
),
question_quality as (
  select
    p.owneruserid as user_id,
    avg(p.score) filter (where p.posttypeid = 1) as avg_question_score,
    percentile_cont(0.9) within group (order by p.viewcount) filter (where p.posttypeid = 1) as p90_question_views,
    count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as questions_with_accepted,
    count(*) filter (where p.posttypeid = 1 and p.answercount >= 5) as highly_answered_questions
  from posts p
  group by p.owneruserid
),
answer_quality as (
  select
    p.owneruserid as user_id,
    avg(p.score) filter (where p.posttypeid = 2) as avg_answer_score,
    count(*) filter (where p.posttypeid = 2 and p.score >= 5) as high_scoring_answers,
    sum(case when p.posttypeid = 2 and exists (
      select 1
      from posts q
      where q.id = p.parentid
        and q.acceptedanswerid = p.id
    ) then 1 else 0 end) as accepted_answers
  from posts p
  group by p.owneruserid
),
tag_influence as (
  select
    q.owneruserid as user_id,
    t.tagname,
    count(*) as tag_q_count,
    sum(q.viewcount) as tag_views,
    row_number() over (partition by q.owneruserid order by sum(q.viewcount) desc nulls last, count(*) desc) as tag_rank
  from posts q
  cross join lateral (
    select unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  ) t
  where q.posttypeid = 1
    and q.tags is not null
  group by q.owneruserid, t.tagname
),
dup_activity as (
  select
    pl.postid as post_id,
    pl.relatedpostid as related_id,
    pl.linktypeid,
    pl.creationdate,
    case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
  from postlinks pl
),
post_close_reasons as (
  select
    ph.postid,
    max(case when ph.posthistorytypeid = 10 then cast(ph.comment as integer) end) as last_close_reason_id,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_close_date
  from posthistory ph
  where ph.posthistorytypeid in (10)
  group by ph.postid
),
question_engagement as (
  select
    q.owneruserid as user_id,
    count(distinct c.id) as comments_on_questions,
    count(distinct v.id) filter (where v.votetypeid in (2,3)) as votes_on_questions,
    count(distinct dl.post_id) as duplicates_marked,
    count(distinct dl.related_id) as duplicates_of
  from posts q
  left join comments c on c.postid = q.id
  left join votes v on v.postid = q.id
  left join dup_activity dl on dl.post_id = q.id and dl.is_duplicate = 1
  where q.posttypeid = 1
  group by q.owneruserid
),
user_last_activity as (
  select
    u.id as user_id,
    greatest(
      coalesce(ua.last_post_activity, timestamp 'epoch'),
      coalesce(cs.last_comment_date, timestamp 'epoch'),
      coalesce(va.last_vote_date, timestamp 'epoch'),
      coalesce(br.last_badge_date, timestamp 'epoch')
    ) as last_activity
  from users u
  left join user_activity ua on ua.user_id = u.id
  left join comment_stats cs on cs.user_id = u.id
  left join vote_agg va on va.user_id = u.id
  left join badge_rollup br on br.user_id = u.id
),
user_ranks as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ua.questions,
    ua.answers,
    qa.avg_question_score,
    aq.avg_answer_score,
    cs.comments,
    va.upvotes_cast,
    va.downvotes_cast,
    br.total_badges,
    br.gold_badges,
    br.silver_badges,
    br.bronze_badges,
    qa.questions_with_accepted,
    aq.accepted_answers,
    qa.p90_question_views,
    coalesce(qa.highly_answered_questions,0) as highly_answered_questions,
    ue.comments_on_questions,
    ue.votes_on_questions,
    ru.website_normalized,
    la.last_activity,
    dense_rank() over (order by coalesce(aq.accepted_answers,0) desc, coalesce(ua.answers,0) desc, coalesce(qa.avg_question_score, -1) desc) as answerer_rank,
    dense_rank() over (order by coalesce(qa.questions_with_accepted,0) desc, coalesce(ua.questions,0) desc, coalesce(qa.p90_question_views,0) desc) as asker_rank,
    row_number() over (order by coalesce(br.gold_badges,0) desc, coalesce(br.silver_badges,0) desc, coalesce(br.bronze_badges,0) desc, ru.reputation desc) as badge_rank
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join question_quality qa on qa.user_id = ru.user_id
  left join answer_quality aq on aq.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join vote_agg va on va.user_id = ru.user_id
  left join badge_rollup br on br.user_id = ru.user_id
  left join question_engagement ue on ue.user_id = ru.user_id
  left join user_last_activity la on la.user_id = ru.user_id
),
top_tags as (
  select
    ti.user_id,
    string_agg(ti.tagname || ':' || cast(ti.tag_views as text), ', ' order by ti.tag_rank) as top3_tags
  from tag_influence ti
  where ti.tag_rank <= 3
  group by ti.user_id
),
closed_reason_names as (
  select
    crt.id as close_reason_id,
    crt.name as close_reason_name
  from closereasontypes crt
)
select
  ur.user_id,
  ur.displayname,
  ur.reputation,
  ur.questions,
  ur.answers,
  ur.avg_question_score,
  ur.avg_answer_score,
  ur.questions_with_accepted,
  ur.accepted_answers,
  ur.highly_answered_questions,
  ur.p90_question_views,
  ur.comments as comments_made,
  ur.upvotes_cast,
  ur.downvotes_cast,
  ur.total_badges,
  ur.gold_badges,
  ur.silver_badges,
  ur.bronze_badges,
  ur.comments_on_questions,
  ur.votes_on_questions,
  ur.website_normalized,
  coalesce(tt.top3_tags, '(none)') as top_tags_by_views,
  ur.answerer_rank,
  ur.asker_rank,
  ur.badge_rank,
  ur.last_activity,
  crn.close_reason_name as most_recent_close_reason_for_top_question
from user_ranks ur
left join lateral (
  select
    q.id as question_id
  from posts q
  where q.owneruserid = ur.user_id
    and q.posttypeid = 1
  order by q.viewcount desc nulls last, q.score desc nulls last, q.creationdate desc nulls last, q.id desc
  limit 1
) topq on true
left join post_close_reasons pcr on pcr.postid = topq.question_id
left join closed_reason_names crn on crn.close_reason_id = pcr.last_close_reason_id
left join top_tags tt on tt.user_id = ur.user_id
where (coalesce(ur.answers,0) + coalesce(ur.questions,0) + coalesce(ur.comments,0)) > 0
  and (
    ur.answerer_rank <= 100
    or ur.asker_rank <= 100
    or ur.badge_rank <= 100
  )
order by
  ur.answerer_rank,
  ur.asker_rank,
  ur.badge_rank,
  ur.user_id
limit 500;