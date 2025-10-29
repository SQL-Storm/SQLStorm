with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as domain,
         row_number() over (partition by coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown')
                            order by u.reputation desc, u.id) as rep_rank_in_domain
  from users u
  where u.creationdate >= (select max(p.creationdate) - interval '3 years' from posts p)
),
top_domains as (
  select domain
  from recent_users
  group by domain
  having count(*) >= 10
),
user_scores as (
  select u.id as user_id,
         sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes_on_posts,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_count,
         count(distinct case when v.votetypeid in (8,9) then v.id end) as bounties_touched
  from users u
  left join posts p on p.owneruserid = u.id
  left join votes v on v.postid = p.id
  group by u.id
),
question_activity as (
  select q.id as question_id,
         q.owneruserid as asker_id,
         q.creationdate as q_creation,
         q.score as q_score,
         q.viewcount,
         q.answercount,
         q.tags,
         q.acceptedanswerid,
         count(a.id) as total_answers,
         max(a.score) as max_answer_score,
         min(a.creationdate) filter (where a.creationdate > q.creationdate) as first_answer_time,
         count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as duplicate_of_count
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  left join postlinks pl on pl.postid = q.id and pl.linktypeid in (1,3)
  where q.posttypeid = 1
    and q.creationdate >= (select max(p2.creationdate) - interval '3 years' from posts p2)
  group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.answercount, q.tags, q.acceptedanswerid
),
accepted_answerers as (
  select aa.id as answer_id,
         aa.parentid as question_id,
         aa.owneruserid as answerer_id,
         aa.score as answer_score,
         aa.creationdate as a_creation
  from posts aa
  join posts q on q.id = aa.parentid and q.posttypeid = 1
  where aa.posttypeid = 2
    and q.acceptedanswerid = aa.id
),
tag_expansion as (
  select qa.question_id,
         unnest(string_to_array(substring(qa.tags from 2 for length(qa.tags)-2), '><')) as tagname
  from question_activity qa
  where qa.tags is not null
),
tag_rank as (
  select te.tagname,
         count(*) as q_count,
         sum(case when qa.q_score > 0 then 1 else 0 end) as positive_q,
         avg(cast(qa.q_score as numeric)) as avg_q_score
  from tag_expansion te
  join question_activity qa on qa.question_id = te.question_id
  group by te.tagname
),
interesting_tags as (
  select tr.tagname
  from tag_rank tr
  where tr.q_count >= 20
     or (tr.avg_q_score > 1 and tr.positive_q >= 10)
),
user_badge_summary as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         sum(case when b.tagbased = true then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
post_history_flags as (
  select ph.postid,
         max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
         max(case when ph.posthistorytypeid in (11,13) then 1 else 0 end) as was_reopened_or_undeleted,
         max(case when ph.posthistorytypeid in (19) then 1 else 0 end) as was_protected
  from posthistory ph
  group by ph.postid
),
comment_polarity as (
  select c.postid,
         sum(case when c.score >= 0 then 1 else 0 end) as nonneg_comments,
         sum(case when c.score < 0 then 1 else 0 end) as neg_comments,
         avg(cast(c.score as numeric)) as avg_comment_score,
         max(c.creationdate) as last_comment_time
  from comments c
  group by c.postid
),
domain_user_selection as (
  select ru.*
  from recent_users ru
  join top_domains td on td.domain = ru.domain
  where ru.rep_rank_in_domain <= 50
),
qualified_questions as (
  select qa.*,
         phf.was_closed_or_migrated,
         phf.was_reopened_or_undeleted,
         phf.was_protected,
         cp.nonneg_comments,
         cp.neg_comments,
         cp.avg_comment_score,
         cp.last_comment_time
  from question_activity qa
  left join post_history_flags phf on phf.postid = qa.question_id
  left join comment_polarity cp on cp.postid = qa.question_id
),
user_engagement as (
  select qu.question_id,
         qu.asker_id,
         du.user_id as matched_user_id,
         du.domain,
         us.net_votes_on_posts,
         us.favorites_count,
         coalesce(ubs.gold_badges,0) as gold_badges,
         coalesce(ubs.silver_badges,0) as silver_badges,
         coalesce(ubs.bronze_badges,0) as bronze_badges,
         coalesce(ubs.tag_badges,0) as tag_badges
  from qualified_questions qu
  join domain_user_selection du
    on du.user_id = qu.asker_id
  left join user_scores us on us.user_id = du.user_id
  left join user_badge_summary ubs on ubs.userid = du.user_id
),
answerer_stats as (
  select aa.question_id,
         aa.answerer_id,
         aa.answer_score,
         rank() over (partition by aa.question_id order by aa.answer_score desc, aa.answer_id) as ans_score_rank
  from accepted_answerers aa
),
question_scoring as (
  select ue.question_id,
         ue.asker_id,
         ue.matched_user_id,
         ue.domain,
         ue.net_votes_on_posts,
         ue.favorites_count,
         ue.gold_badges, ue.silver_badges, ue.bronze_badges, ue.tag_badges,
         qq.q_creation,
         qq.q_score,
         qq.viewcount,
         qq.answercount,
         qq.total_answers,
         qq.max_answer_score,
         qq.first_answer_time,
         qq.duplicate_of_count,
         qq.was_closed_or_migrated,
         qq.was_reopened_or_undeleted,
         qq.was_protected,
         qq.nonneg_comments,
         qq.neg_comments,
         qq.avg_comment_score,
         qq.last_comment_time,
         coalesce(min(case when te.tagname in (select tagname from interesting_tags) then 1 else null end), 0) as has_interesting_tag
  from user_engagement ue
  join qualified_questions qq on qq.question_id = ue.question_id
  left join tag_expansion te on te.question_id = ue.question_id
  group by ue.question_id, ue.asker_id, ue.matched_user_id, ue.domain,
           ue.net_votes_on_posts, ue.favorites_count, ue.gold_badges, ue.silver_badges, ue.bronze_badges, ue.tag_badges,
           qq.q_creation, qq.q_score, qq.viewcount, qq.answercount, qq.total_answers, qq.max_answer_score, qq.first_answer_time,
           qq.duplicate_of_count, qq.was_closed_or_migrated, qq.was_reopened_or_undeleted, qq.was_protected,
           qq.nonneg_comments, qq.neg_comments, qq.avg_comment_score, qq.last_comment_time
),
final_rank as (
  select qs.*,
         extract(epoch from (coalesce(qs.first_answer_time, qs.q_creation) - qs.q_creation)) as seconds_to_first_answer,
         (coalesce(qs.q_score,0) * 2
          + coalesce(qs.viewcount,0) / 100.0
          + coalesce(qs.total_answers,0) * 1.5
          + coalesce(qs.max_answer_score,0) * 1.0
          - coalesce(qs.neg_comments,0) * 0.5
          + coalesce(qs.nonneg_comments,0) * 0.25
          + case when qs.was_closed_or_migrated = 1 then -5 else 0 end
          + case when qs.was_protected = 1 then 1 else 0 end
          + case when qs.has_interesting_tag = 1 then 3 else 0 end
          + least(coalesce(qs.net_votes_on_posts,0), 100) / 10.0
          + (coalesce(qs.gold_badges,0) * 3 + coalesce(qs.silver_badges,0) * 1.5 + coalesce(qs.bronze_badges,0) * 0.5)
         ) as composite_score
  from question_scoring qs
),
top_n as (
  select fr.*,
         dense_rank() over (order by fr.composite_score desc, fr.q_creation desc, fr.question_id) as global_rank
  from final_rank fr
)
select
  t.global_rank,
  t.question_id,
  t.asker_id,
  u.displayname as asker_displayname,
  t.domain as asker_domain,
  t.q_creation,
  t.q_score,
  t.viewcount,
  t.total_answers,
  t.max_answer_score,
  t.seconds_to_first_answer,
  t.was_closed_or_migrated,
  t.was_protected,
  t.has_interesting_tag,
  t.composite_score,
  aa.answerer_id as accepted_answerer_id,
  u2.displayname as accepted_answerer_name,
  ars.ans_score_rank as accepted_answerer_rank_for_q
from top_n t
left join answerer_stats ars on ars.question_id = t.question_id and ars.ans_score_rank = 1
left join accepted_answerers aa on aa.question_id = t.question_id
left join users u on u.id = t.asker_id
left join users u2 on u2.id = aa.answerer_id
where t.global_rank <= 200
order by t.global_rank, t.question_id;