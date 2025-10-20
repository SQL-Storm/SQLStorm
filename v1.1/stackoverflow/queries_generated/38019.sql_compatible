with recent_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
active_questions as (
  select p.id as question_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.owneruserid as asker_id,
         p.title,
         p.tags
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
answers as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answerer_id,
         a.creationdate,
         a.score
  from posts a
  where a.posttypeid = 2
),
answerers as (
  select a.question_id, a.answerer_id, min(a.creationdate) as first_answer_time
  from answers a
  group by a.question_id, a.answerer_id
),
first_answers as (
  select a.question_id, a.answerer_id, a.creationdate as answer_time
  from answers a
  join (
    select question_id, min(creationdate) as first_time
    from answers
    group by question_id
  ) fa on fa.question_id = a.question_id and fa.first_time = a.creationdate
),
question_commenters as (
  select c.postid as question_id, c.userid as commenter_id, min(c.creationdate) as first_comment_time
  from comments c
  join active_questions q on q.question_id = c.postid
  where c.userid is not null
  group by c.postid, c.userid
),
engagement as (
  select
    q.question_id,
    q.title,
    q.asker_id,
    u.displayname as asker_name,
    q.creationdate as question_time,
    q.viewcount,
    q.score as question_score,
    count(distinct a.answer_id) as answer_count,
    count(distinct qc.commenter_id) as unique_commenters,
    min(a.creationdate) as first_answer_time,
    min(qc.first_comment_time) as first_comment_time
  from active_questions q
  left join answers a on a.question_id = q.question_id
  left join question_commenters qc on qc.question_id = q.question_id
  left join users u on u.id = q.asker_id
  group by q.question_id, q.title, q.asker_id, u.displayname, q.creationdate, q.viewcount, q.score
),
answerers_stats as (
  select
    a.question_id,
    count(distinct a.answerer_id) as distinct_answerers,
    cast(avg(u.reputation) as numeric(18,2)) as avg_answerer_rep,
    percentile_cont(0.5) within group (order by u.reputation) as median_answerer_rep
  from answerers a
  join users u on u.id = a.answerer_id
  group by a.question_id
),
badges_last_year as (
  select b.userid, count(*) as badges_count
  from badges b
  where b.date >= (select max(date) - interval '365 days' from badges)
  group by b.userid
),
votes_agg as (
  select
    v.postid as question_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
  from votes v
  join active_questions q on q.question_id = v.postid
  group by v.postid
),
duplicate_links as (
  select pl.postid as question_id, count(*) as duplicate_count
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid
),
tag_expansion as (
  select
    q.question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
  from active_questions q
  where q.tags is not null and q.tags <> ''
),
top_tags as (
  select
    te.question_id,
    array_agg(te.tag order by t.count desc, te.tag) as tags_by_global_popularity
  from tag_expansion te
  left join tags t on t.tagname = te.tag
  group by te.question_id
),
time_to_firsts as (
  select
    e.question_id,
    extract(epoch from (e.first_answer_time - e.question_time)) as sec_to_first_answer,
    extract(epoch from (e.first_comment_time - e.question_time)) as sec_to_first_comment
  from engagement e
),
asker_profile as (
  select
    q.question_id,
    u.reputation as asker_rep,
    coalesce(b.badges_count, 0) as asker_badges_year
  from active_questions q
  left join users u on u.id = q.asker_id
  left join badges_last_year b on b.userid = q.asker_id
),
ranked_questions as (
  select
    e.question_id,
    e.title,
    e.asker_id,
    e.asker_name,
    e.question_time,
    e.viewcount,
    e.question_score,
    e.answer_count,
    e.unique_commenters,
    coalesce(v.upvotes,0) as upvotes,
    coalesce(v.downvotes,0) as downvotes,
    coalesce(v.favorites,0) as favorites,
    coalesce(d.duplicate_count,0) as duplicate_count,
    s.distinct_answerers,
    s.avg_answerer_rep,
    s.median_answerer_rep,
    t.tags_by_global_popularity,
    tt.sec_to_first_answer,
    tt.sec_to_first_comment,
    ap.asker_rep,
    ap.asker_badges_year,
    row_number() over (
      order by
        coalesce(e.answer_count,0) desc,
        coalesce(e.viewcount,0) desc,
        coalesce(v.upvotes,0) desc,
        e.question_time desc
    ) as popularity_rank
  from engagement e
  left join votes_agg v on v.question_id = e.question_id
  left join duplicate_links d on d.question_id = e.question_id
  left join answerers_stats s on s.question_id = e.question_id
  left join top_tags t on t.question_id = e.question_id
  left join time_to_firsts tt on tt.question_id = e.question_id
  left join asker_profile ap on ap.question_id = e.question_id
),
rolling_activity as (
  select
    q.question_id,
    cast(q.creationdate as date) as day,
    count(*) over (partition by cast(q.creationdate as date)) as questions_per_day,
    avg(q.viewcount) over (partition by cast(q.creationdate as date)) as avg_views_per_day
  from active_questions q
),
final as (
  select
    rq.*,
    ra.questions_per_day,
    ra.avg_views_per_day,
    case when rq.sec_to_first_answer is not null then rq.sec_to_first_answer/3600.0 end as hours_to_first_answer,
    case when rq.sec_to_first_comment is not null then rq.sec_to_first_comment/3600.0 end as hours_to_first_comment,
    (coalesce(rq.upvotes,0) - coalesce(rq.downvotes,0)) as net_votes,
    case
      when rq.answer_count > 0 then cast(rq.viewcount as numeric) / rq.answer_count
      else null
    end as views_per_answer,
    case
      when rq.distinct_answerers > 0 then rq.avg_answerer_rep
      else null
    end as avg_rep_if_answered
  from ranked_questions rq
  left join rolling_activity ra on ra.question_id = rq.question_id
)
select *
from final
where question_score >= 0
order by popularity_rank, question_time desc
limit 500;