-- {"query": "49.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2773} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm
  from users u
  where u.creationdate >= date_trunc('month', now()) - interval '24 months'
),
question_posts as (
  select p.id,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.answercount,
         p.closeddate
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select p.id,
         p.parentid as question_id,
         p.owneruserid,
         p.score,
         p.creationdate
  from posts p
  where p.posttypeid = 2
),
votes_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
         sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
  from votes v
  group by v.postid
),
comment_stats as (
  select c.postid,
         count(*) as comment_count,
         max(c.creationdate) as last_comment_at,
         sum(case when c.score > 0 then 1 else 0 end) as pos_comments
  from comments c
  group by c.postid
),
user_badge_pivot as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
duplicate_links as (
  select pl.postid as dup_post_id,
         count(*) filter (where pl.linktypeid = 3) as duplicate_count
  from postlinks pl
  group by pl.postid
),
edit_events as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_count,
         max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as last_edit_at,
         count(*) filter (where ph.posthistorytypeid = 10) as close_votes_events,
         max((ph.comment)::int) filter (where ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$') as last_close_reason_raw
  from posthistory ph
  group by ph.postid
),
close_reasons as (
  select crt.id as close_reason_id,
         crt.name as close_reason_name
  from closereasontypes crt
),
question_enriched as (
  select qp.id as question_id,
         qp.owneruserid,
         qp.creationdate as question_created_at,
         qp.score as question_score,
         qp.viewcount,
         qp.title,
         qp.tags,
         qp.answercount,
         qp.closeddate,
         va.upvotes,
         va.downvotes,
         va.favorites,
         va.bounty_started,
         va.bounty_awarded,
         cs.comment_count,
         cs.last_comment_at,
         cs.pos_comments,
         de.duplicate_count,
         ee.edit_count,
         ee.last_edit_at,
         ee.close_votes_events,
         ee.last_close_reason_raw
  from question_posts qp
  left join votes_agg va on va.postid = qp.id
  left join comment_stats cs on cs.postid = qp.id
  left join duplicate_links de on de.dup_post_id = qp.id
  left join edit_events ee on ee.postid = qp.id
),
qa_activity as (
  select qe.question_id,
         qe.owneruserid as asker_id,
         ru.displayname as asker_name,
         qe.title,
         qe.tags,
         qe.question_created_at,
         qe.question_score,
         qe.viewcount,
         coalesce(qe.upvotes,0) as q_up,
         coalesce(qe.downvotes,0) as q_down,
         coalesce(qe.favorites,0) as q_favs,
         coalesce(qe.comment_count,0) as q_comments,
         coalesce(qe.edit_count,0) as q_edits,
         coalesce(qe.duplicate_count,0) as q_dups,
         qe.closeddate,
         qe.last_edit_at,
         qe.last_comment_at,
         qe.bounty_started,
         qe.bounty_awarded,
         ubp.gold_badges,
         ubp.silver_badges,
         ubp.bronze_badges,
         ubp.tag_badges,
         ru.reputation as asker_rep,
         ru.creationdate as asker_since,
         ru.location as asker_loc,
         ru.websiteurl_norm,
         (select count(*) from answer_posts ap where ap.question_id = qe.question_id) as actual_answers,
         (select max(ap.score) from answer_posts ap where ap.question_id = qe.question_id) as max_answer_score,
         (select avg(ap.score)::numeric(10,2) from answer_posts ap where ap.question_id = qe.question_id) as avg_answer_score
  from question_enriched qe
  left join recent_users ru on ru.user_id = qe.owneruserid
  left join user_badge_pivot ubp on ubp.userid = qe.owneruserid
),
answerer_rollup as (
  select ap.question_id,
         count(distinct ap.owneruserid) as distinct_answerers,
         sum(case when ap.score > 0 then 1 else 0 end) as positive_answers,
         sum(case when ap.score < 0 then 1 else 0 end) as negative_answers,
         max(ap.creationdate) as last_answer_at
  from answer_posts ap
  group by ap.question_id
),
tag_explode as (
  select q.question_id,
         unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
  from qa_activity q
  where q.tags is not null and length(q.tags) > 2
),
tag_rank as (
  select te.tag,
         count(*) as tag_q_count,
         rank() over (order by count(*) desc) as tag_rank_by_q
  from tag_explode te
  group by te.tag
),
question_tag_stats as (
  select te.question_id,
         count(*) as tag_count,
         min(tr.tag_rank_by_q) as best_tag_rank
  from tag_explode te
  join tag_rank tr on tr.tag = te.tag
  group by te.question_id
),
scores_window as (
  select q.*,
         row_number() over (order by q.viewcount desc nulls last) as rn_by_views,
         row_number() over (order by q.question_score desc nulls last) as rn_by_score,
         ntile(10) over (order by coalesce(q.question_score,0) + coalesce(q.q_up,0) - coalesce(q.q_down,0) desc) as decile_engagement
  from qa_activity q
),
closed_reason_resolved as (
  select qe.question_id,
         cr.close_reason_name
  from question_enriched qe
  left join close_reasons cr
    on cr.close_reason_id = qe.last_close_reason_raw
),
final_union as (
  select s.question_id,
         s.asker_id,
         s.asker_name,
         s.title,
         coalesce(qts.tag_count, 0) as tag_count,
         qts.best_tag_rank,
         s.question_created_at,
         s.question_score,
         s.viewcount,
         s.q_up, s.q_down, s.q_favs,
         s.q_comments, s.q_edits, s.q_dups,
         s.closeddate,
         arr.distinct_answerers,
         arr.positive_answers,
         arr.negative_answers,
         arr.last_answer_at,
         s.max_answer_score,
         s.avg_answer_score,
         s.bounty_started,
         s.bounty_awarded,
         s.asker_rep,
         s.gold_badges, s.silver_badges, s.bronze_badges, s.tag_badges,
         s.rn_by_views,
         s.rn_by_score,
         s.decile_engagement,
         crr.close_reason_name,
         case
           when s.closeddate is not null and coalesce(s.q_dups,0) > 0 then 'ClosedDuplicate'
           when s.closeddate is not null then 'ClosedOther'
           when s.actual_answers = 0 and s.viewcount > 1000 then 'UnansweredHighView'
           when s.actual_answers >= 5 and s.question_score >= 5 then 'HotAnswered'
           else 'Normal'
         end as bucket,
         coalesce(nullif(trim(s.websiteurl_norm), 'N/A'), 'unknown') as website_norm2
  from scores_window s
  left join answerer_rollup arr on arr.question_id = s.question_id
  left join question_tag_stats qts on qts.question_id = s.question_id
  left join closed_reason_resolved crr on crr.question_id = s.question_id
  where s.question_created_at >= now() - interval '18 months'
  union all
  select s.question_id,
         s.asker_id,
         s.asker_name,
         s.title,
         coalesce(qts.tag_count, 0) as tag_count,
         qts.best_tag_rank,
         s.question_created_at,
         s.question_score,
         s.viewcount,
         s.q_up, s.q_down, s.q_favs,
         s.q_comments, s.q_edits, s.q_dups,
         s.closeddate,
         arr.distinct_answerers,
         arr.positive_answers,
         arr.negative_answers,
         arr.last_answer_at,
         s.max_answer_score,
         s.avg_answer_score,
         s.bounty_started,
         s.bounty_awarded,
         s.asker_rep,
         s.gold_badges, s.silver_badges, s.bronze_badges, s.tag_badges,
         s.rn_by_views,
         s.rn_by_score,
         s.decile_engagement,
         crr.close_reason_name,
         'Legacy' as bucket,
         coalesce(nullif(trim(s.websiteurl_norm), 'N/A'), 'unknown') as website_norm2
  from scores_window s
  left join answerer_rollup arr on arr.question_id = s.question_id
  left join question_tag_stats qts on qts.question_id = s.question_id
  left join closed_reason_resolved crr on crr.question_id = s.question_id
  where s.question_created_at < now() - interval '18 months'
),
ranked as (
  select f.*,
         dense_rank() over (
           partition by f.bucket
           order by coalesce(f.viewcount,0) desc, coalesce(f.question_score,0) desc, coalesce(f.q_favs,0) desc
         ) as bucket_rank,
         sum(case when f.positive_answers > f.negative_answers then 1 else 0 end) over (partition by f.bucket) as bucket_pos_dom_count
  from final_union f
),
null_logic_probe as (
  select r.*,
         case when r.closeddate is null then 0 else 1 end as is_closed_flag,
         coalesce(r.close_reason_name, case when r.closeddate is not null then 'UnknownReason' end) as close_reason_fallback,
         nullif(r.asker_name, '') as asker_name_nullif
  from ranked r
)
select *
from null_logic_probe
where (
        (bucket in ('ClosedDuplicate','ClosedOther') and q_dups >= 1)
        or (bucket = 'HotAnswered' and distinct_answerers >= 3)
        or (bucket = 'UnansweredHighView' and q_comments >= 2)
      )
  and coalesce(tag_count, 0) between 1 and 5
  and coalesce(question_score, 0) + coalesce(q_up,0) - coalesce(q_down,0) >= 0
  and (
        (asker_rep >= 1000 and coalesce(gold_badges,0) >= 1)
        or (asker_rep < 1000 and coalesce(bronze_badges,0) >= 3)
      )
order by bucket, bucket_rank
limit 500;