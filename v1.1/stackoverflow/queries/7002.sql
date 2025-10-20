with
Questions as (
  select p.id, p.title, p.creationdate, p.owneruserid, p.score, p.viewcount,
         coalesce(p.answercount,0) as answercount,
         regexp_split_to_table(substring(p.tags from 2 for length(p.tags)-2), '><') as tag
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
),
QuestionStats as (
  select q.id,
         q.title,
         q.creationdate,
         q.owneruserid,
         q.score,
         q.viewcount,
         q.answercount,
         q.tag,
         (length(coalesce(q.title,'')) +
          (length(coalesce((select body from posts where id = q.id),'')) / nullif(nullif(length(coalesce((select body from posts where id = q.id),'')),0),1)) * 0.01
         ) as text_complexity
  from Questions q
),
AnswersRanked as (
  select a.id as answerid,
         a.parentid as questionid,
         a.owneruserid as answererid,
         a.score as answerscore,
         a.creationdate as answerdate,
         a.commentcount,
         row_number() over (partition by a.parentid order by a.score desc, a.creationdate asc) as rn,
         dense_rank() over (partition by a.parentid order by a.score desc) as dr,
         case when exists(select 1 from posts q where q.id = a.parentid and q.acceptedanswerid = a.id) then 1 else 0 end as is_accepted,
         (select count(*) from votes v where v.postid = a.id and v.votetypeid in (2,3)) as answer_vote_events
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
),
QuestionAggregates as (
  select qs.id as questionid,
         qs.title,
         qs.creationdate,
         qs.owneruserid,
         qs.score as qscore,
         qs.viewcount,
         qs.answercount,
         qs.tag,
         qs.text_complexity,
         coalesce(sum(ar.answerscore) filter (where ar.rn <= 3),0) as top3_answer_score_sum,
         max(ar.is_accepted) as has_accepted_answer,
         coalesce(max(ar.answer_vote_events),0) as max_answer_vote_events,
         count(distinct a.id) as total_answers_reported
  from QuestionStats qs
  left join posts a on a.parentid = qs.id and a.posttypeid = 2
  left join AnswersRanked ar on ar.questionid = qs.id
  group by qs.id, qs.title, qs.creationdate, qs.owneruserid, qs.score, qs.viewcount, qs.answercount, qs.tag, qs.text_complexity
),
UserActivity as (
  select u.id as userid,
         u.reputation,
         u.creationdate,
         u.displayname,
         u.views,
         u.upvotes,
         u.downvotes,
         (select count(*) from posts p where p.owneruserid = u.id and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year') as posts_last_year,
         (select count(*) from comments c where c.userid = u.id and c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year') as comments_last_year,
         (select count(*) from votes v where v.userid = u.id and v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year') as votes_last_year,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.reputation, u.creationdate, u.displayname, u.views, u.upvotes, u.downvotes
),
TagMetrics as (
  select t.tagname,
         t.count as tag_count,
         t.excerptpostid,
         t.wikipostid,
         percent_rank() over (order by t.count) as popularity_pr
  from tags t
),
CandidateQuestions as (
  select qa.questionid,
         qa.title,
         qa.creationdate,
         qa.owneruserid,
         ua.displayname,
         ua.reputation,
         ua.posts_last_year,
         qa.qscore,
         qa.viewcount,
         qa.answercount,
         qa.tag,
         tm.tag_count,
         tm.popularity_pr,
         qa.text_complexity,
         qa.top3_answer_score_sum,
         qa.has_accepted_answer,
         qa.max_answer_vote_events,
         qa.total_answers_reported,
         cast(
           coalesce(qa.qscore,0) * 1.5
           + ln(nullif(1 + qa.viewcount,0)) * 2.3
           + (case when qa.has_accepted_answer = 1 then 50 else 0 end)
           + (coalesce(ua.reputation,0) / nullif(1000,0)) * greatest(1, least(10, coalesce(ua.posts_last_year,0)/nullif(1,0)))
           + (coalesce(qa.text_complexity,0) * power(coalesce(qa.top3_answer_score_sum,0)+1, 0.6))
           - (coalesce(tm.popularity_pr,0) * 20)
           - (case when qa.total_answers_reported = 0 then 15 else 0 end)
         as numeric(18,6)) as benchmark_score
  from QuestionAggregates qa
  left join UserActivity ua on ua.userid = qa.owneruserid
  left join TagMetrics tm on tm.tagname = qa.tag
),
RankedPerTag as (
  select cq.*,
         row_number() over (partition by cq.tag order by cq.benchmark_score desc, cq.creationdate asc) as tag_rank,
         rank() over (partition by cq.tag order by cq.benchmark_score desc) as tag_rank_dense
  from CandidateQuestions cq
),
RelatedLinks as (
  select pl.postid as source_q, pl.relatedpostid as related_p, lt.name as link_type, pl.creationdate as link_date
  from postlinks pl
  left join linktypes lt on lt.id = pl.linktypeid
  where pl.postid in (select questionid from RankedPerTag where tag_rank <= 500)
    and pl.relatedpostid is not null
  union
  select pl.relatedpostid as source_q, pl.postid as related_p, lt.name as link_type, pl.creationdate as link_date
  from postlinks pl
  left join linktypes lt on lt.id = pl.linktypeid
  where pl.relatedpostid in (select questionid from RankedPerTag where tag_rank <= 500)
),
LinkCounts as (
  select r.source_q as questionid,
         count(*) filter (where r.link_type ilike '%Duplicate%' or r.link_type ilike '%Linked%') as link_events_recent,
         min(r.link_date) as first_link_date
  from RelatedLinks r
  where r.link_date >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
  group by r.source_q
)
select rpt.tag,
       rpt.tag_rank,
       rpt.questionid,
       rpt.title,
       rpt.creationdate,
       rpt.displayname as owner,
       rpt.reputation,
       rpt.qscore,
       rpt.viewcount,
       rpt.answercount,
       rpt.has_accepted_answer,
       rpt.top3_answer_score_sum,
       rpt.max_answer_vote_events,
       rpt.text_complexity,
       rpt.benchmark_score,
       coalesce(lc.link_events_recent,0) as link_events_recent,
       coalesce(lc.first_link_date, rpt.creationdate) as first_link_date,
       left(concat_ws(' | ',
              rpt.tag,
              rpt.title,
              'score='||cast(rpt.benchmark_score as text),
              case when rpt.has_accepted_answer=1 then 'Accepted' else 'NoAccept' end,
              'owner='||coalesce(rpt.displayname,'[unknown]')
           ), 400) as summary_snippet
from RankedPerTag rpt
left join LinkCounts lc on lc.questionid = rpt.questionid
where rpt.tag_rank <= 5
  and rpt.benchmark_score is not null
  and (rpt.reputation is null or rpt.reputation >= 0)
order by rpt.tag, rpt.benchmark_score desc, rpt.creationdate asc;