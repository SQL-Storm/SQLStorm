-- {"query": "57.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2396} 
with
-- recent active questions augmented
recent_qs as (
  select p.id,
         p.title,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         coalesce(p.answercount,0) as answercount,
         p.tags,
         substring(p.tags from 2 for char_length(p.tags)-2) as tags_inner,
         array_remove(string_to_array(substring(coalesce(p.tags,''),2, greatest(0,char_length(coalesce(p.tags,''))-2)), '><'), '') as tag_array
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (cast('2024-10-01 12:34:56' as timestamp) - interval '365 days')
),
-- top answerers in last year via window
answerers as (
  select a.owneruserid,
         count(*) filter (where a.score>0) as positive_answers,
         count(*) as total_answers,
         avg(a.score) as avg_answer_score,
         max(a.score) as max_answer_score,
         row_number() over (order by count(*) desc, avg(a.score) desc) as rn
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= (cast('2024-10-01 12:34:56' as timestamp) - interval '365 days')
    and a.owneruserid is not null
  group by a.owneruserid
  having count(*) >= 5
),
-- compute user badge richness and recency
user_badges as (
  select u.id as userid,
         u.displayname,
         count(b.id) as badge_count,
         sum(case when b.class = 1 then 1 else 0 end) as gold,
         sum(case when b.class = 2 then 1 else 0 end) as silver,
         sum(case when b.class = 3 then 1 else 0 end) as bronze,
         max(b.date) as last_badge_date,
         bool_or(b.tagbased) as has_tagbadges
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.displayname
),
-- for each question, top 3 answers + gap to accepted answer (if any)
answers_ranked as (
  select a.*,
         row_number() over (partition by a.parentid order by a.score desc, a.creationdate asc) as ans_rank,
         dense_rank() over (partition by a.parentid order by a.score desc) as ans_dense_rank
  from posts a
  where a.posttypeid = 2
),
top_answers as (
  select ar.parentid as questionid,
         ar.id as answerid,
         ar.owneruserid as answer_owner,
         ar.score as answer_score,
         ar.creationdate as answer_creation,
         ar.ans_rank,
         ar.ans_dense_rank
  from answers_ranked ar
  where ar.ans_rank <= 3
),
-- compute comment sentiment-ish indicators via heuristics
comment_signals as (
  select c.postid,
         count(*) as comment_count,
         sum(case when length(c.text) > 200 then 1 else 0 end) as long_comments,
         sum(case when c.score >= 2 then 1 else 0 end) as highly_upvoted_comments,
         sum(case when c.text ilike '%thanks%' or c.text ilike '%thank you%' then 1 else 0 end) as thanks_count,
         max(c.creationdate) as last_comment_date
  from comments c
  group by c.postid
),
-- tag popularity snapshot last year (approx)
tag_pop as (
  select t.tagname,
         sum((p.score)::bigint) as tag_score_sum,
         count(p.id) as tag_question_count,
         percentile_cont(0.5) within group (order by p.viewcount) as median_views
  from tags t
  left join posts p on p.posttypeid = 1 and p.tags like ('%<' || t.tagname || '>%')
  where t.tagname is not null
    and p.creationdate >= (cast('2024-10-01 12:34:56' as timestamp) - interval '365 days')
  group by t.tagname
),
-- correlated subquery: for each question compute number of duplicate links and linked posts score aggregates
link_aggregates as (
  select pl.postid,
         sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_links,
         sum(case when pl.linktypeid = 1 then 1 else 0 end) as outward_links,
         count(*) as total_links,
         max(rp.score) as max_related_score,
         avg(rp.score) as avg_related_score
  from postlinks pl
  left join posts rp on rp.id = pl.relatedpostid
  group by pl.postid
),
-- closure and history signals
history_signals as (
  select ph.postid,
         sum(case when ph.posthistorytypeid in (10,11) then 1 else 0 end) as close_reopen_events,
         sum(case when ph.posthistorytypeid in (12) then 1 else 0 end) as deletions,
         sum(case when ph.posthistorytypeid in (24) then 1 else 0 end) as sugg_edits_applied,
         max(ph.creationdate) as last_history_event
  from posthistory ph
  group by ph.postid
),
-- combine main dataset
question_enriched as (
  select q.*,
         coalesce(csig.comment_count,0) as comment_count,
         coalesce(csig.long_comments,0) as long_comments,
         coalesce(lk.duplicate_links,0) as duplicate_links,
         coalesce(lk.outward_links,0) as outward_links,
         coalesce(hs.close_reopen_events,0) as close_reopen_events,
         coalesce(hs.sugg_edits_applied,0) as sugg_edits_applied,
         (select count(*) from posts a where a.parentid = q.id and a.score >= q.score) as answers_notably_better_than_question,
         (select count(*) from votes v where v.postid = q.id and v.votetypeid = 5) as favorites_count,
         (select count(*) from votes v where v.postid = q.id and v.votetypeid = 2) as upvotes_count,
         (select count(*) from votes v where v.postid = q.id and v.votetypeid = 3) as downvotes_count
  from recent_qs q
  left join comment_signals csig on csig.postid = q.id
  left join link_aggregates lk on lk.postid = q.id
  left join history_signals hs on hs.postid = q.id
),
-- final scoring with complex expressions, null logic, string ops and windowing
scored_questions as (
  select qe.id,
         qe.title,
         qe.owneruserid,
         u.displayname as owner_name,
         qe.creationdate,
         qe.score,
         qe.viewcount,
         qe.answercount,
         qe.comment_count,
         qe.duplicate_links,
         qe.outward_links,
         qe.close_reopen_events,
         qe.sugg_edits_applied,
         coalesce(tb.answer_score_sum,0) as top3_answer_score_sum,
         coalesce(tb.top3_count,0) as top3_count,
         (case when qe.tags is null or qe.tags = '' then '{}' else qe.tag_array end) as tag_list,
         -- complex score combining multiple signals with null-safe math and type casts
         (coalesce(qe.score,0) * 1.5
          + greatest(coalesce(qe.viewcount,0)::numeric / nullif(greatest(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - qe.creationdate)),1),0), 0) * 0.25
          + ln(1 + coalesce(qe.comment_count,0)) * 3.0
          + sqrt(coalesce(tb.top3_count,0)) * 2.5
          - least(coalesce(qe.duplicate_links,0),5) * 1.2
          - (case when qe.close_reopen_events > 0 then 8 else 0 end)
          + (coalesce((select ub.badge_count from user_badges ub where ub.userid = qe.owneruserid),0)) * 0.8
         ) as composite_score,
         row_number() over (order by
           (coalesce(qe.score,0) * 1.5
            + greatest(coalesce(qe.viewcount,0)::numeric / nullif(greatest(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - qe.creationdate)),1),0), 0) * 0.25
            + ln(1 + coalesce(qe.comment_count,0)) * 3.0
            + sqrt(coalesce(tb.top3_count,0)) * 2.5
            - least(coalesce(qe.duplicate_links,0),5) * 1.2
            - (case when qe.close_reopen_events > 0 then 8 else 0 end)
            + (coalesce((select ub.badge_count from user_badges ub where ub.userid = qe.owneruserid),0)) * 0.8
           ) desc,
           qe.viewcount desc,
           qe.creationdate desc
         ) as rank_within_window
  from question_enriched qe
  left join lateral (
    select sum(a.score) as answer_score_sum, count(*) as top3_count
    from posts a
    where a.parentid = qe.id
      and a.posttypeid = 2
      and a.id in (select id from answers_ranked ar where ar.parentid = qe.id and ar.ans_rank <= 3)
  ) tb on true
  left join users u on u.id = qe.owneruserid
)
select sq.*,
       -- enrich with tag-level aggregate joins (explode top tag)
       (select tp.tag_score_sum from tag_pop tp where tp.tagname = (sq.tag_list[1]) limit 1) as top_tag_score_sum,
       (select tp.tag_question_count from tag_pop tp where tp.tagname = (sq.tag_list[1]) limit 1) as top_tag_question_count,
       -- correlated correlated: presence of an accepted answer and its delta
       (select a.score from posts a where a.id = (select p.acceptedanswerid from posts p where p.id = sq.id) limit 1) as accepted_answer_score,
       (select case when (select p.acceptedanswerid from posts p where p.id = sq.id) is not null
                    then (sq.composite_score - coalesce((select a.score from posts a where a.id = (select p.acceptedanswerid from posts p where p.id = sq.id) limit 1),0))
                    else null end) as score_minus_accepted,
       -- example of set operator: union of related post ids (duplicates + linked)
       (select array_agg(distinct rp) from (
           select relatedpostid as rp from postlinks where postid = sq.id and linktypeid = 3
           union
           select relatedpostid as rp from postlinks where postid = sq.id and linktypeid = 1
        ) x) as related_posts_list
from scored_questions sq
where sq.rank_within_window <= 200
order by sq.composite_score desc, sq.viewcount desc;