-- {"query": "750.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3451} 
with recent_users as (
  select u.id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
tagged_questions as (
  select p.id as question_id,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.answercount,
         p.commentcount,
         p.favoritecount,
         p.title,
         p.tags,
         case when p.closeddate is not null then 1 else 0 end as is_closed
  from posts p
  where p.posttypeid = 1
),
answers as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid,
         a.creationdate,
         a.score as answer_score
  from posts a
  where a.posttypeid = 2
),
question_windows as (
  select q.*,
         row_number() over (partition by date_trunc('month', q.creationdate) order by q.score desc nulls last, q.viewcount desc nulls last, q.id) as rn_month_top,
         avg(q.score) over (partition by date_trunc('month', q.creationdate)) as avg_score_month,
         percentile_cont(0.9) within group (order by q.viewcount) over (partition by date_trunc('month', q.creationdate)) as p90_views_month,
         sum(coalesce(q.viewcount,0)) over (partition by q.owneruserid) as total_owner_views
  from tagged_questions q
),
user_badge_stats as (
  select b.userid,
         count(*) as badge_count,
         sum(case when b.class = 1 then 1 else 0 end) as gold_count,
         sum(case when b.class = 2 then 1 else 0 end) as silver_count,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
         min(b.date) as first_badge_at,
         max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
vote_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
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
close_events as (
  select ph.postid,
         min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_at,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_at,
         count(*) filter (where ph.posthistorytypeid = 10) as close_votes,
         max(case when ph.posthistorytypeid = 10 then nullif(ph.comment, '')::int end) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
duplicates as (
  select pl.postid as dup_post_id,
         pl.relatedpostid as original_post_id,
         pl.creationdate as dup_link_date
  from postlinks pl
  where pl.linktypeid = 3
),
tag_array as (
  select q.id as question_id,
         string_to_array(substring(q.tags, 2, length(q.tags)-2), '><') as tag_list
  from posts q
  where q.posttypeid = 1
),
target_tags as (
  select t.question_id,
         unnest(t.tag_list) as tagname
  from tag_array t
),
ranked_answers as (
  select a.*,
         dense_rank() over (partition by a.question_id order by a.answer_score desc nulls last, a.creationdate asc, a.answer_id) as ans_rank
  from answers a
),
owner_activity as (
  select u.id as user_id,
         count(distinct q.id) as questions_authored,
         count(distinct a.answer_id) as answers_authored,
         sum(coalesce(q.viewcount,0)) as views_on_questions,
         sum(coalesce(va.upvotes,0) - coalesce(va.downvotes,0)) as net_votes_on_posts
  from users u
  left join posts q on q.posttypeid = 1 and q.owneruserid = u.id
  left join vote_agg va on va.postid = q.id
  left join answers a on a.owneruserid = u.id
  group by u.id
),
hot_question_candidates as (
  select qw.*
  from question_windows qw
  where qw.rn_month_top <= 50
),
monthly_baseline as (
  select date_trunc('month', q.creationdate) as month_bucket,
         avg(q.viewcount) as avg_views_month,
         stddev_pop(q.viewcount) as sd_views_month,
         avg(q.score) as avg_score_month,
         stddev_pop(q.score) as sd_score_month
  from tagged_questions q
  group by date_trunc('month', q.creationdate)
),
question_enriched as (
  select q.id,
         q.creationdate,
         q.title,
         q.tags,
         q.owneruserid,
         q.score,
         q.viewcount,
         q.answercount,
         q.commentcount,
         q.favoritecount,
         q.is_closed,
         coalesce(va.upvotes,0) as upvotes,
         coalesce(va.downvotes,0) as downvotes,
         coalesce(va.favorites,0) as favorites_votes,
         coalesce(va.bounty_total,0) as bounty_total,
         coalesce(ca.comment_count,0) as comments_total,
         ca.last_comment_at,
         ce.first_close_at,
         ce.last_reopen_at,
         ce.close_votes,
         ce.last_close_reason_id,
         du.original_post_id as duplicate_of,
         du.dup_link_date,
         case
           when position('java' in lower(coalesce(q.title,''))) > 0 then 1
           when exists (
             select 1 from target_tags tt
             where tt.question_id = q.id and lower(tt.tagname) in ('java','javascript','.net')
           ) then 1
           else 0
         end as is_target_topic,
         row_number() over (order by q.viewcount desc nulls last, q.score desc nulls last, q.id) as global_popularity_rank
  from question_windows q
  left join vote_agg va on va.postid = q.id
  left join comment_agg ca on ca.postid = q.id
  left join close_events ce on ce.postid = q.id
  left join duplicates du on du.dup_post_id = q.id
),
user_enriched as (
  select ru.id as user_id,
         ru.displayname,
         ru.reputation,
         ru.creationdate as user_created_at,
         ru.location,
         ru.websiteurl_norm,
         coalesce(ubs.badge_count,0) as badge_count,
         coalesce(ubs.gold_count,0) as gold_count,
         coalesce(ubs.silver_count,0) as silver_count,
         coalesce(ubs.bronze_count,0) as bronze_count,
         uact.questions_authored,
         uact.answers_authored,
         uact.views_on_questions,
         uact.net_votes_on_posts
  from recent_users ru
  left join user_badge_stats ubs on ubs.userid = ru.id
  left join owner_activity uact on uact.user_id = ru.id
),
question_scores as (
  select qe.id,
         qe.owneruserid,
         qe.creationdate,
         qe.title,
         qe.tags,
         qe.viewcount,
         qe.score,
         qe.answercount,
         qe.commentcount,
         qe.favoritecount,
         qe.is_closed,
         qe.upvotes,
         qe.downvotes,
         qe.favorites_votes,
         qe.bounty_total,
         qe.comments_total,
         qe.last_comment_at,
         qe.first_close_at,
         qe.last_reopen_at,
         qe.close_votes,
         qe.last_close_reason_id,
         qe.duplicate_of,
         qe.dup_link_date,
         qe.is_target_topic,
         qe.global_popularity_rank,
         mb.month_bucket,
         mb.avg_views_month,
         mb.sd_views_month,
         mb.avg_score_month,
         mb.sd_score_month,
         case when mb.sd_views_month > 0 then (qe.viewcount - mb.avg_views_month) / mb.sd_views_month else null end as z_views,
         case when mb.sd_score_month > 0 then (qe.score - mb.avg_score_month) / mb.sd_score_month else null end as z_score,
         -- complexity: weighted engagement score
         (coalesce(qe.viewcount,0) * 0.05
          + coalesce(qe.upvotes,0) * 3
          - coalesce(qe.downvotes,0) * 2
          + coalesce(qe.answercount,0) * 4
          + coalesce(qe.comments_total,0) * 0.5
          + coalesce(qe.favorites_votes,0) * 2
          + coalesce(qe.bounty_total,0) * 0.01
          - case when qe.is_closed = 1 then 10 else 0 end
          - case when qe.duplicate_of is not null then 8 else 0 end
         ) as engagement_score
  from question_enriched qe
  left join monthly_baseline mb on mb.month_bucket = date_trunc('month', qe.creationdate)
),
answer_summary as (
  select ra.question_id,
         count(*) as answer_cnt,
         max(case when ra.ans_rank = 1 then ra.answer_score end) as top_answer_score,
         min(ra.creationdate) as first_answer_at,
         max(ra.creationdate) as last_answer_at,
         avg(ra.answer_score) as avg_answer_score
  from ranked_answers ra
  group by ra.question_id
),
owner_quality as (
  select qe.owneruserid as user_id,
         avg(case when qs.engagement_score is not null then qs.engagement_score end) as avg_engagement_score,
         avg(qe.score) as avg_question_score,
         avg(qe.viewcount) as avg_question_views,
         count(*) filter (where qe.is_target_topic = 1) as target_topic_qs,
         sum(case when qe.is_closed = 1 then 1 else 0 end) as closed_qs
  from question_scores qs
  join question_enriched qe on qe.id = qs.id
  group by qe.owneruserid
),
final_scored as (
  select
    qs.id as question_id,
    qs.owneruserid,
    ue.displayname,
    ue.reputation,
    ue.location,
    ue.websiteurl_norm,
    ue.badge_count,
    ue.gold_count,
    ue.silver_count,
    ue.bronze_count,
    ue.questions_authored,
    ue.answers_authored,
    ue.views_on_questions,
    ue.net_votes_on_posts,
    qs.creationdate,
    qs.title,
    qs.tags,
    qs.viewcount,
    qs.score,
    qs.answercount,
    qs.commentcount,
    qs.favoritecount,
    qs.is_closed,
    qs.upvotes,
    qs.downvotes,
    qs.favorites_votes,
    qs.bounty_total,
    qs.comments_total,
    qs.last_comment_at,
    qs.first_close_at,
    qs.last_reopen_at,
    qs.close_votes,
    qs.last_close_reason_id,
    qs.duplicate_of,
    qs.dup_link_date,
    qs.is_target_topic,
    qs.global_popularity_rank,
    qs.z_views,
    qs.z_score,
    qs.engagement_score,
    asu.answer_cnt,
    asu.top_answer_score,
    asu.first_answer_at,
    asu.last_answer_at,
    asu.avg_answer_score,
    oq.avg_engagement_score as owner_avg_engagement,
    oq.avg_question_score as owner_avg_qscore,
    oq.avg_question_views as owner_avg_qviews,
    oq.target_topic_qs as owner_target_topic_qs,
    oq.closed_qs as owner_closed_qs,
    -- final composite score mixes question- and owner-level signals with recency decay
    (
      coalesce(qs.engagement_score,0) * 0.6
      + coalesce(qs.z_views,0) * 10
      + coalesce(qs.z_score,0) * 6
      + coalesce(asu.top_answer_score,0) * 1.5
      + greatest(0, least(50, ue.reputation/100.0)) * 0.8
      + coalesce(oq.avg_engagement_score,0) * 0.4
      - case when qs.is_closed = 1 then 5 else 0 end
      - case when qs.duplicate_of is not null then 3 else 0 end
    ) * exp(-extract(epoch from (now() - qs.creationdate)) / 86400.0 / 365.0) as composite_score
  from question_scores qs
  left join answer_summary asu on asu.question_id = qs.id
  left join user_enriched ue on ue.user_id = qs.owneruserid
  left join owner_quality oq on oq.user_id = qs.owneruserid
  where
    -- complicated predicate with null logic and string handling
    (
      qs.is_target_topic = 1
      or (
        qs.viewcount > coalesce(qs.avg_views_month, 0) + coalesce(qs.sd_views_month, 0)
        and (qs.z_score is null or qs.z_score >= -1.0)
      )
      or (
        qs.title is not null
        and length(regexp_replace(lower(qs.title), '\s+', '', 'g')) >= 10
      )
    )
    and (
      (qs.last_close_reason_id is distinct from 101) -- not recently closed as duplicate by reason id
      or qs.duplicate_of is null
    )
),
topk as (
  select *,
         row_number() over (order by composite_score desc nulls last, viewcount desc nulls last, score desc nulls last, question_id) as rk
  from final_scored
)
select
  fk.question_id,
  fk.displayname as owner_displayname,
  fk.reputation as owner_reputation,
  fk.location as owner_location,
  fk.badge_count,
  fk.gold_count,
  fk.silver_count,
  fk.bronze_count,
  fk.creationdate as question_created_at,
  fk.title,
  fk.tags,
  fk.viewcount,
  fk.score,
  fk.answercount,
  fk.commentcount,
  fk.favoritecount,
  fk.upvotes,
  fk.downvotes,
  fk.bounty_total,
  fk.comments_total,
  fk.is_closed,
  fk.duplicate_of,
  fk.global_popularity_rank,
  round(fk.z_views::numeric, 3) as z_views,
  round(fk.z_score::numeric, 3) as z_score,
  round(fk.engagement_score::numeric, 2) as engagement_score,
  round(fk.composite_score::numeric, 2) as composite_score,
  fk.first_close_at,
  fk.last_reopen_at,
  fk.last_comment_at
from topk fk
where fk.rk <= 200
order by fk.composite_score desc nulls last, fk.viewcount desc nulls last, fk.score desc nulls last, fk.question_id;