with recent_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
hot_questions as (
  select p.id as question_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.owneruserid,
         p.tags,
         coalesce(p.favoritecount, 0) as favoritecount,
         coalesce(p.answercount, 0) as answercount
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '730 days' from posts)
),
answers as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answerer_id,
         a.score as answer_score,
         a.creationdate as answer_date
  from posts a
  where a.posttypeid = 2
),
votes_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_legacy,
         count(*) as total_votes,
         min(v.creationdate) as first_vote_at,
         max(v.creationdate) as last_vote_at
  from votes v
  where v.creationdate >= (select max(creationdate) - interval '730 days' from votes)
  group by v.postid
),
comments_agg as (
  select c.postid,
         count(*) as comment_count,
         max(c.creationdate) as last_comment_at,
         sum(case when c.score > 0 then c.score else 0 end) as comment_karma
  from comments c
  group by c.postid
),
tagged as (
  select hq.question_id,
         unnest(string_to_array(substring(hq.tags, 2, length(hq.tags)-2), '><')) as tag
  from hot_questions hq
  where hq.tags is not null and length(hq.tags) > 2
),
top_tags as (
  select t.tag,
         count(*) as tag_q_count
  from tagged t
  group by t.tag
  having count(*) >= 50
),
question_engagement as (
  select hq.question_id,
         hq.creationdate as q_created,
         hq.score as q_score,
         hq.viewcount as q_views,
         hq.favoritecount + coalesce(va.favorites_legacy, 0) as favorites_total,
         coalesce(hq.answercount, 0) as answers_declared,
         coalesce(va.upvotes, 0) as upvotes,
         coalesce(va.downvotes, 0) as downvotes,
         coalesce(va.total_votes, 0) as total_votes,
         va.first_vote_at,
         va.last_vote_at,
         coalesce(ca.comment_count, 0) as comment_count,
         coalesce(ca.comment_karma, 0) as comment_karma
  from hot_questions hq
  left join votes_agg va on va.postid = hq.question_id
  left join comments_agg ca on ca.postid = hq.question_id
),
answerers as (
  select a.question_id,
         a.answerer_id,
         count(*) as answers_count,
         max(a.answer_score) as best_answer_score,
         min(a.answer_date) as first_answer_at
  from answers a
  group by a.question_id, a.answerer_id
),
best_answerers as (
  select a1.question_id,
         a1.answerer_id,
         a1.answers_count,
         a1.best_answer_score,
         a1.first_answer_at,
         row_number() over (partition by a1.question_id order by a1.answers_count desc, a1.best_answer_score desc, a1.first_answer_at asc) as rk
  from answerers a1
),
user_reach as (
  select u.id as user_id,
         sum(coalesce(p.viewcount, 0)) as total_views_contributed,
         sum(case when p.posttypeid = 2 then coalesce(p.score, 0) else 0 end) as answer_score_sum,
         sum(case when p.posttypeid = 1 then coalesce(p.score, 0) else 0 end) as question_score_sum
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
recent_activity_bursts as (
  select ph.postid,
         count(*) as bursts,
         min(ph.creationdate) as first_event_at,
         max(ph.creationdate) as last_event_at
  from posthistory ph
  where ph.posthistorytypeid in (10,11,12,13,14,15,24,31,33,34,35,36,50,52,53)
    and ph.creationdate >= (select max(creationdate) - interval '365 days' from posthistory)
  group by ph.postid
),
dup_links as (
  select pl.postid as dup_post_id,
         pl.relatedpostid as target_post_id,
         pl.creationdate as link_date
  from postlinks pl
  where pl.linktypeid = 3
),
question_tags_filtered as (
  select t.question_id, t.tag
  from tagged t
  join top_tags tt on tt.tag = t.tag
),
question_tag_pivot as (
  select qt.question_id,
         array_agg(qt.tag order by qt.tag) as tags_array
  from question_tags_filtered qt
  group by qt.question_id
),
ranked_questions as (
  select qe.question_id,
         qe.q_created,
         qe.q_score,
         qe.q_views,
         qe.favorites_total,
         qe.answers_declared,
         qe.upvotes,
         qe.downvotes,
         qe.total_votes,
         qe.comment_count,
         qe.comment_karma,
         coalesce(rab.bursts, 0) as moderation_bursts,
         coalesce(
           case
             when qe.last_vote_at is not null and qe.first_vote_at is not null
             then extract(epoch from (qe.last_vote_at - qe.first_vote_at)) / 3600.0
             else 0
           end
         , 0) as vote_window_hours,
         coalesce(qtp.tags_array, array[]::text[]) as tags_array,
         0.4 * ln(1 + greatest(qe.q_views, 0)) +
         0.3 * greatest(qe.q_score, 0) +
         0.15 * greatest(qe.upvotes - qe.downvotes, 0) +
         0.1 * greatest(qe.comment_count, 0) +
         0.05 * greatest(qe.favorites_total, 0) -
         0.1 * greatest(qe.downvotes, 0) +
         0.05 * greatest(coalesce(rab.bursts, 0), 0) as engagement_score
  from question_engagement qe
  left join recent_activity_bursts rab on rab.postid = qe.question_id
  left join question_tag_pivot qtp on qtp.question_id = qe.question_id
),
accepted_map as (
  select p.id as question_id, p.acceptedanswerid
  from posts p
  where p.posttypeid = 1 and p.acceptedanswerid is not null
),
answer_quality as (
  select a.question_id,
         sum(case when a.answer_score >= 5 then 1 else 0 end) as good_answers,
         sum(case when a.answer_score < 0 then 1 else 0 end) as bad_answers,
         avg(a.answer_score) as avg_answer_score
  from answers a
  group by a.question_id
),
top_contributors as (
  select ba.question_id,
         ba.answerer_id,
         ba.answers_count,
         ba.best_answer_score,
         ba.first_answer_at
  from best_answerers ba
  where ba.rk = 1
),
question_owner as (
  select p.id as question_id, p.owneruserid as owner_id
  from posts p
  where p.posttypeid = 1
),
user_summary as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         coalesce(ur.total_views_contributed, 0) as total_views_contributed,
         coalesce(ur.answer_score_sum, 0) as answer_score_sum,
         coalesce(ur.question_score_sum, 0) as question_score_sum
  from users u
  left join user_reach ur on ur.user_id = u.id
),
final as (
  select rq.question_id,
         rq.q_created,
         rq.q_score,
         rq.q_views,
         rq.favorites_total,
         rq.upvotes,
         rq.downvotes,
         rq.total_votes,
         rq.comment_count,
         rq.comment_karma,
         rq.moderation_bursts,
         rq.vote_window_hours,
         rq.tags_array,
         rq.engagement_score,
         coalesce(aq.good_answers, 0) as good_answers,
         coalesce(aq.bad_answers, 0) as bad_answers,
         coalesce(aq.avg_answer_score, 0) as avg_answer_score,
         case when am.acceptedanswerid is not null then 1 else 0 end as has_accepted_answer,
         tc.answerer_id as top_answerer_id,
         tc.answers_count as top_answerer_answers_count,
         tc.best_answer_score as top_answerer_best_score,
         us_top.displayname as top_answerer_name,
         us_top.reputation as top_answerer_rep,
         qo.owner_id as owner_user_id,
         us_owner.displayname as owner_name,
         us_owner.reputation as owner_rep
  from ranked_questions rq
  left join answer_quality aq on aq.question_id = rq.question_id
  left join accepted_map am on am.question_id = rq.question_id
  left join top_contributors tc on tc.question_id = rq.question_id
  left join user_summary us_top on us_top.user_id = tc.answerer_id
  left join question_owner qo on qo.question_id = rq.question_id
  left join user_summary us_owner on us_owner.user_id = qo.owner_id
)
select *
from final
where q_views >= 100
  and engagement_score > 1.0
order by engagement_score desc, q_score desc, q_views desc
limit 250;