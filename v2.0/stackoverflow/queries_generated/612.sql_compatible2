with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
         row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
top_tags as (
  select t.tagname,
         t.count,
         t.isrequired,
         t.ismoderatoronly,
         dense_rank() over (order by t.count desc, t.tagname) as dr
  from tags t
),
question_core as (
  select p.id as question_id,
         p.owneruserid as asker_id,
         p.creationdate as q_created,
         p.score as q_score,
         p.viewcount as q_views,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.answercount,
         coalesce(p.favoritecount, 0) as fav_count,
         p.closeddate,
         (p.closeddate is not null) as is_closed
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from posts where posttypeid = 1)
),
answer_core as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answerer_id,
         a.creationdate as a_created,
         a.score as a_score
  from posts a
  where a.posttypeid = 2
),
accept_latency as (
  select qc.question_id,
         qc.acceptedanswerid,
         min(case when ac.answer_id = qc.acceptedanswerid then ac.a_created end) as accepted_time,
         qc.q_created,
         extract(epoch from (min(case when ac.answer_id = qc.acceptedanswerid then ac.a_created end) - qc.q_created)) / 3600.0 as hours_to_accept
  from question_core qc
  left join answer_core ac on ac.question_id = qc.question_id
  group by qc.question_id, qc.acceptedanswerid, qc.q_created
),
vote_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  where v.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from votes)
  group by v.postid
),
comment_agg as (
  select c.postid,
         count(*) as comment_count,
         max(c.creationdate) as last_comment_at,
         sum(case when c.score > 0 then 1 else 0 end) as positive_comments
  from comments c
  group by c.postid
),
postlink_agg as (
  select pl.postid,
         sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
         sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count
  from postlinks pl
  group by pl.postid
),
closed_reasons as (
  select ph.postid,
         min(ph.creationdate) as first_closed_at,
         max(case
             when ph.posthistorytypeid = 10 then
               nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '')
             else null
           end) as last_close_reason_code
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
tag_expand as (
  select qc.question_id,
         unnest(string_to_array(substring(qc.tags, 2, length(qc.tags)-2), '><')) as tag
  from question_core qc
  where qc.tags is not null and qc.tags like '<%>'
),
q_tag_stats as (
  select te.question_id,
         count(*) as tag_count,
         sum(case when tt.dr <= 100 then 1 else 0 end) as top100_tag_hits,
         max(tt.dr) filter (where tt.dr is not null) as worst_rank
  from tag_expand te
  left join top_tags tt on lower(tt.tagname) = lower(te.tag)
  group by te.question_id
),
user_activity as (
  select u.id as user_id,
         count(distinct p.id) filter (where p.posttypeid = 1) as questions_posted,
         count(distinct p.id) filter (where p.posttypeid = 2) as answers_posted,
         count(distinct c.id) as comments_made,
         sum(coalesce(vu.votes_cast,0)) as votes_cast
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join (
    select userid, count(*) as votes_cast
    from votes
    where userid is not null
    group by userid
  ) vu on vu.userid = u.id
  group by u.id
),
answerer_quality as (
  select ac.answerer_id as user_id,
         count(*) as answers_total,
         avg(cast(ac.a_score as numeric)) as avg_answer_score,
         sum(case when ac.a_score >= 1 then 1 else 0 end) as answers_nonneg,
         percentile_cont(0.9) within group (order by ac.a_score) as p90_answer_score
  from answer_core ac
  group by ac.answerer_id
),
question_enrichment as (
  select qc.question_id,
         qc.asker_id,
         qc.q_created,
         qc.q_score,
         qc.q_views,
         qc.title,
         qc.answercount,
         qc.acceptedanswerid,
         coalesce(va.upvotes,0) as q_up,
         coalesce(va.downvotes,0) as q_down,
         coalesce(va.favorites,0) as q_fav_votes,
         coalesce(va.bounty_total,0) as q_bounty,
         coalesce(ca.comment_count,0) as q_comments,
         ca.last_comment_at,
         coalesce(pl.linked_count,0) as q_linked,
         coalesce(pl.duplicate_count,0) as q_duplicates,
         coalesce(cr.first_closed_at, null) as first_closed_at,
         cr.last_close_reason_code,
         coalesce(qts.tag_count,0) as tag_count,
         coalesce(qts.top100_tag_hits,0) as top100_tag_hits,
         qts.worst_rank,
         al.hours_to_accept,
         case
           when qc.closeddate is not null then 'Closed'
           when qc.acceptedanswerid is not null then 'Answered'
           when qc.answercount > 0 then 'HasAnswers'
           else 'OpenNoAnswers'
         end as q_status
  from question_core qc
  left join vote_agg va on va.postid = qc.question_id
  left join comment_agg ca on ca.postid = qc.question_id
  left join postlink_agg pl on pl.postid = qc.question_id
  left join closed_reasons cr on cr.postid = qc.question_id
  left join q_tag_stats qts on qts.question_id = qc.question_id
  left join accept_latency al on al.question_id = qc.question_id
),
answer_enrichment as (
  select ac.question_id,
         count(*) as answers_total,
         sum(case when ac.a_score > 0 then 1 else 0 end) as pos_answers,
         avg(cast(ac.a_score as numeric)) as avg_answer_score,
         max(ac.a_score) as max_answer_score,
         min(ac.a_score) as min_answer_score,
         max(ac.a_created) as last_answer_at
  from answer_core ac
  group by ac.question_id
),
owner_profile as (
  select u.id as user_id,
         u.reputation,
         u.displayname,
         u.location,
         ua.questions_posted,
         ua.answers_posted,
         ua.comments_made,
         ua.votes_cast,
         aq.answers_total as answers_contributed,
         aq.avg_answer_score,
         aq.p90_answer_score
  from users u
  left join user_activity ua on ua.user_id = u.id
  left join answerer_quality aq on aq.user_id = u.id
),
ranked_questions as (
  select qe.question_id,
         qe.q_created,
         qe.title,
         qe.q_status,
         qe.q_score,
         qe.q_views,
         qe.q_up,
         qe.q_down,
         qe.q_fav_votes,
         qe.q_bounty,
         qe.tag_count,
         qe.top100_tag_hits,
         coalesce(ae.answers_total, 0) as answers_total,
         coalesce(ae.pos_answers, 0) as pos_answers,
         coalesce(ae.avg_answer_score, NULL) as avg_answer_score,
         coalesce(ae.max_answer_score, NULL) as max_answer_score,
         coalesce(ae.min_answer_score, NULL) as min_answer_score,
         coalesce(ae.last_answer_at, NULL) as last_answer_at,
         qe.asker_id,
         qe.hours_to_accept,
         qe.first_closed_at,
         qe.last_close_reason_code,
         qe.q_comments,
         qe.last_comment_at,
         qe.q_linked,
         qe.q_duplicates,
         op.reputation as asker_rep,
         op.answers_contributed as asker_answers_total,
         op.avg_answer_score as asker_avg_answer_score,
         row_number() over (
           partition by case when qe.q_status = 'Closed' then 'Closed' else 'Open' end
           order by
             coalesce(qe.hours_to_accept, 1e9) asc,
             qe.q_score desc,
             qe.q_views desc,
             (qe.q_up - qe.q_down) desc,
             qe.q_fav_votes desc,
             qe.tag_count desc
         ) as bucket_rank
  from question_enrichment qe
  left join answer_enrichment ae on ae.question_id = qe.question_id
  left join owner_profile op on op.user_id = qe.asker_id
  group by
    qe.question_id, qe.q_created, qe.title, qe.q_status, qe.q_score, qe.q_views,
    qe.q_up, qe.q_down, qe.q_fav_votes, qe.q_bounty, qe.tag_count, qe.top100_tag_hits,
    coalesce(ae.answers_total, 0), coalesce(ae.pos_answers, 0), coalesce(ae.avg_answer_score, NULL),
    coalesce(ae.max_answer_score, NULL), coalesce(ae.min_answer_score, NULL), coalesce(ae.last_answer_at, NULL),
    qe.asker_id, qe.hours_to_accept, qe.first_closed_at, qe.last_close_reason_code,
    qe.q_comments, qe.last_comment_at, qe.q_linked, qe.q_duplicates,
    op.reputation, op.answers_contributed, op.avg_answer_score
),
dupe_chain as (
  select pl.postid as question_id,
         array_agg(distinct pl.relatedpostid order by pl.relatedpostid) as dup_of_ids
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid
),
final as (
  select rq.question_id,
         rq.q_created,
         rq.title,
         rq.q_status,
         rq.q_score,
         rq.q_views,
         rq.q_up, rq.q_down, rq.q_fav_votes,
         rq.q_bounty,
         rq.tag_count,
         rq.top100_tag_hits,
         rq.answers_total,
         rq.pos_answers,
         rq.avg_answer_score,
         rq.max_answer_score,
         rq.min_answer_score,
         rq.hours_to_accept,
         rq.first_closed_at,
         rq.last_close_reason_code,
         rq.q_comments,
         rq.last_comment_at,
         rq.q_linked,
         rq.q_duplicates,
         rq.asker_id,
         rq.asker_rep,
         rq.asker_answers_total,
         rq.asker_avg_answer_score,
         dc.dup_of_ids,
         case
           when rq.top100_tag_hits > 0 then 'PopularTag'
           when rq.tag_count >= 5 then 'ManyTags'
           else 'Other'
         end as tag_profile,
         case
           when rq.q_duplicates > 0 and rq.q_status = 'Closed' then 1
           when rq.q_duplicates > 0 then 2
           when rq.first_closed_at is not null then 3
           else 4
         end as moderation_severity,
         rq.bucket_rank
  from ranked_questions rq
  left join dupe_chain dc on dc.question_id = rq.question_id
)
select f.question_id,
       f.q_created,
       f.title,
       f.q_status,
       f.q_score,
       f.q_views,
       f.q_up,
       f.q_down,
       f.q_fav_votes,
       f.q_bounty,
       f.tag_count,
       f.top100_tag_hits,
       f.answers_total,
       f.pos_answers,
       f.avg_answer_score,
       f.max_answer_score,
       f.min_answer_score,
       f.hours_to_accept,
       f.first_closed_at,
       f.last_close_reason_code,
       f.q_comments,
       f.last_comment_at,
       f.q_linked,
       f.q_duplicates,
       f.asker_id,
       f.asker_rep,
       f.asker_answers_total,
       f.asker_avg_answer_score,
       f.dup_of_ids,
       f.tag_profile,
       f.moderation_severity,
       f.bucket_rank
from final f
where (
        f.moderation_severity <= 2
        or (f.q_status <> 'Closed' and (f.answers_total >= 3 or coalesce(f.hours_to_accept, 1e9) < 24))
      )
  and (
        exists (
          select 1
          from tag_expand te
          where te.question_id = f.question_id
            and lower(te.tag) in (
              select lower(tagname)
              from top_tags
              where dr <= 50
            )
        )
        or coalesce(f.asker_rep, 0) >= (
          select percentile_disc(0.75) within group (order by reputation)
          from users
        )
      )
  and coalesce(f.q_views, 0) >= (
        select avg(q_views) from ranked_questions
      )
order by
  f.moderation_severity asc,
  f.bucket_rank asc,
  f.q_score desc,
  f.q_views desc
limit 250;