-- {"query": "832.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3341} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         date_trunc('month', u.creationdate) as coh_month,
         coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as region_hint
  from users u
  where u.creationdate >= now() - interval '3 years'
),
question_posts as (
  select p.id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.favoritecount,
         p.commentcount,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.closeddate,
         p.posttypeid
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select p.id,
         p.owneruserid as user_id,
         p.parentid as question_id,
         p.creationdate,
         p.score,
         p.commentcount
  from posts p
  where p.posttypeid = 2
),
activity_by_user as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.coh_month,
         ru.region_hint,
         count(distinct qp.id) as q_count,
         count(distinct ap.id) filter (where ap.score > 0) as pos_a_count,
         count(distinct ap.id) filter (where ap.score <= 0 or ap.score is null) as nonpos_a_count,
         sum(coalesce(qp.viewcount,0)) as q_views,
         sum(coalesce(qp.favoritecount,0)) as q_favs,
         sum(coalesce(qp.commentcount,0)) + sum(coalesce(ap.commentcount,0)) as total_comments,
         count(distinct case when qp.acceptedanswerid is not null then qp.id end) as accepted_qs,
         count(distinct case when qp.closeddate is not null then qp.id end) as closed_qs
  from recent_users ru
  left join question_posts qp on qp.owneruserid = ru.user_id
  left join answer_posts ap on ap.user_id = ru.user_id
  group by ru.user_id, ru.displayname, ru.reputation, ru.coh_month, ru.region_hint
),
votes_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_legacy,
         max(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as max_bounty
  from votes v
  where v.creationdate >= now() - interval '3 years'
  group by v.postid
),
hot_tags as (
  select t.tagname,
         t.count,
         percentile_disc(0.9) within group (order by t.count) over () as p90_cnt
  from tags t
),
user_tag_exposure as (
  select qp.owneruserid as user_id,
         unnest(string_to_array(substring(coalesce(qp.tags,''), 2, greatest(length(coalesce(qp.tags,'')) - 2, 0)), '><')) as tagname
  from question_posts qp
  where qp.creationdate >= now() - interval '3 years'
  union all
  select ap.user_id,
         unnest(string_to_array(substring(coalesce(q.tags,''), 2, greatest(length(coalesce(q.tags,'')) - 2, 0)), '><')) as tagname
  from answer_posts ap
  join posts q on q.id = ap.question_id and q.posttypeid = 1
  where ap.creationdate >= now() - interval '3 years'
),
user_hot_tag_stats as (
  select ute.user_id,
         count(*) filter (where ht.tagname is not null and ht.count >= ht.p90_cnt) as hot_tag_interactions,
         count(*) as all_tag_interactions,
         count(distinct case when ht.tagname is not null and ht.count >= ht.p90_cnt then ht.tagname end) as distinct_hot_tags
  from user_tag_exposure ute
  left join hot_tags ht on lower(ute.tagname) = lower(ht.tagname)
  group by ute.user_id
),
postlink_dups as (
  select pl.postid,
         sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_links
  from postlinks pl
  where pl.creationdate >= now() - interval '3 years'
  group by pl.postid
),
post_edits as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
         min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as first_edit_at
  from posthistory ph
  where ph.creationdate >= now() - interval '3 years'
  group by ph.postid
),
question_quality as (
  select qp.id as question_id,
         qp.owneruserid as user_id,
         coalesce(v.upvotes,0) - coalesce(v.downvotes,0) as net_votes,
         coalesce(v.favorites_legacy,0) + coalesce(qp.favoritecount,0) as fav_score,
         coalesce(pl.dup_links,0) as dup_marks,
         coalesce(pe.edit_events,0) as edits,
         case when qp.acceptedanswerid is not null then 1 else 0 end as has_accepted,
         case when qp.closeddate is null then 0 else 1 end as is_closed,
         coalesce(v.max_bounty,0) as max_bounty
  from question_posts qp
  left join votes_agg v on v.postid = qp.id
  left join postlink_dups pl on pl.postid = qp.id
  left join post_edits pe on pe.postid = qp.id
),
user_question_window as (
  select qq.user_id,
         qq.question_id,
         qq.net_votes,
         qq.fav_score,
         qq.dup_marks,
         qq.edits,
         qq.has_accepted,
         qq.is_closed,
         qq.max_bounty,
         row_number() over (partition by qq.user_id order by qq.net_votes desc nulls last, qq.fav_score desc nulls last, qq.question_id) as rn_best,
         row_number() over (partition by qq.user_id order by qq.net_votes asc nulls first, qq.question_id) as rn_worst
  from question_quality qq
),
best_and_worst_questions as (
  select uqw.user_id,
         max(case when uqw.rn_best = 1 then uqw.question_id end) as best_q_id,
         max(case when uqw.rn_worst = 1 then uqw.question_id end) as worst_q_id,
         max(case when uqw.rn_best = 1 then uqw.net_votes end) as best_q_net_votes,
         max(case when uqw.rn_worst = 1 then uqw.net_votes end) as worst_q_net_votes
  from user_question_window uqw
  group by uqw.user_id
),
user_badges as (
  select b.userid as user_id,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  where b.date >= now() - interval '3 years'
  group by b.userid
),
user_comment_sentiment as (
  select c.userid as user_id,
         avg(nullif(length(c.text),0)) as avg_comment_len,
         avg(case when position('thank' in lower(c.text)) > 0 then 1 else 0 end) as thankfulness_rate,
         sum(case when c.score > 0 then 1 else 0 end) as pos_comment_votes
  from comments c
  where c.creationdate >= now() - interval '3 years'
  group by c.userid
),
user_activity_rank as (
  select abu.*,
         uth.hot_tag_interactions,
         uth.all_tag_interactions,
         uth.distinct_hot_tags,
         coalesce(ub.gold_badges,0) as gold_badges,
         coalesce(ub.silver_badges,0) as silver_badges,
         coalesce(ub.bronze_badges,0) as bronze_badges,
         coalesce(ub.tag_badges,0) as tag_badges,
         coalesce(ucs.avg_comment_len,0) as avg_comment_len,
         coalesce(ucs.thankfulness_rate,0) as thankfulness_rate,
         coalesce(ucs.pos_comment_votes,0) as pos_comment_votes,
         coalesce(bw.best_q_id, -1) as best_q_id,
         coalesce(bw.worst_q_id, -1) as worst_q_id,
         coalesce(bw.best_q_net_votes, 0) as best_q_net_votes,
         coalesce(bw.worst_q_net_votes, 0) as worst_q_net_votes
  from activity_by_user abu
  left join user_hot_tag_stats uth on uth.user_id = abu.user_id
  left join user_badges ub on ub.user_id = abu.user_id
  left join user_comment_sentiment ucs on ucs.user_id = abu.user_id
  left join best_and_worst_questions bw on bw.user_id = abu.user_id
),
scored as (
  select uar.*,
         -- composite activity score with various weights and null-safe arithmetic
         (
           1.0 * coalesce(uar.q_count,0) +
           0.5 * coalesce(uar.pos_a_count,0) +
           0.1 * greatest(coalesce(uar.q_views,0) / nullif(uar.q_count,0), 0) +
           2.0 * coalesce(uar.accepted_qs,0) -
           0.7 * coalesce(uar.closed_qs,0) +
           0.2 * coalesce(uar.total_comments,0) +
           0.8 * coalesce(uar.hot_tag_interactions,0) +
           0.4 * coalesce(uar.distinct_hot_tags,0) +
           3.0 * coalesce(uar.gold_badges,0) +
           1.5 * coalesce(uar.silver_badges,0) +
           0.5 * coalesce(uar.bronze_badges,0) +
           0.3 * coalesce(uar.tag_badges,0) +
           0.05 * coalesce(uar.pos_comment_votes,0) +
           0.02 * coalesce(uar.best_q_net_votes,0) -
           0.01 * abs(coalesce(uar.worst_q_net_votes,0))
         ) as activity_score,
         percentile_cont(0.5) within group (order by coalesce(uar.q_views,0)) over (partition by uar.coh_month) as cohort_median_views,
         dense_rank() over (order by
            (
              1.0 * coalesce(uar.q_count,0) +
              0.5 * coalesce(uar.pos_a_count,0) +
              0.1 * greatest(coalesce(uar.q_views,0) / nullif(uar.q_count,0), 0) +
              2.0 * coalesce(uar.accepted_qs,0) -
              0.7 * coalesce(uar.closed_qs,0) +
              0.8 * coalesce(uar.hot_tag_interactions,0) +
              0.4 * coalesce(uar.distinct_hot_tags,0) +
              3.0 * coalesce(uar.gold_badges,0) +
              1.5 * coalesce(uar.silver_badges,0) +
              0.5 * coalesce(uar.bronze_badges,0)
            ) desc, uar.user_id
         ) as global_rank
  from user_activity_rank uar
),
cohort_stats as (
  select s.coh_month,
         count(*) as users_in_cohort,
         avg(s.activity_score) as avg_activity_score,
         stddev_pop(s.activity_score) as stddev_activity_score,
         percentile_disc(0.9) within group (order by s.activity_score) as p90_activity,
         percentile_disc(0.1) within group (order by s.activity_score) as p10_activity
  from scored s
  group by s.coh_month
),
final_rank as (
  select s.*,
         cs.users_in_cohort,
         cs.avg_activity_score,
         cs.stddev_activity_score,
         cs.p90_activity,
         cs.p10_activity,
         case
           when cs.stddev_activity_score is null or cs.stddev_activity_score = 0 then null
           else (s.activity_score - cs.avg_activity_score) / cs.stddev_activity_score
         end as zscore_in_cohort,
         ntile(10) over (order by s.activity_score desc nulls last) as decile_global,
         ntile(10) over (partition by s.coh_month order by s.activity_score desc nulls last) as decile_in_cohort
  from scored s
  join cohort_stats cs on cs.coh_month = s.coh_month
)
select fr.user_id,
       fr.displayname,
       fr.region_hint,
       fr.coh_month,
       fr.reputation,
       fr.q_count,
       fr.pos_a_count,
       fr.nonpos_a_count,
       fr.q_views,
       fr.q_favs,
       fr.total_comments,
       fr.accepted_qs,
       fr.closed_qs,
       fr.hot_tag_interactions,
       fr.all_tag_interactions,
       fr.distinct_hot_tags,
       fr.gold_badges,
       fr.silver_badges,
       fr.bronze_badges,
       fr.tag_badges,
       fr.avg_comment_len,
       fr.thankfulness_rate,
       fr.pos_comment_votes,
       fr.best_q_id,
       fr.worst_q_id,
       fr.best_q_net_votes,
       fr.worst_q_net_votes,
       round(fr.activity_score::numeric, 3) as activity_score,
       fr.global_rank,
       fr.users_in_cohort,
       round(fr.avg_activity_score::numeric, 3) as cohort_avg_activity,
       round(fr.stddev_activity_score::numeric, 3) as cohort_stddev_activity,
       round(fr.zscore_in_cohort::numeric, 3) as cohort_zscore,
       fr.decile_global,
       fr.decile_in_cohort
from final_rank fr
where coalesce(fr.q_count,0) + coalesce(fr.pos_a_count,0) + coalesce(fr.nonpos_a_count,0) > 0
  and (
    fr.activity_score >= fr.p90_activity
    or (fr.activity_score >= fr.avg_activity_score and fr.decile_in_cohort <= 3)
    or (fr.activity_score >= fr.cohort_median_views and fr.global_rank <= 200)
  )
order by fr.activity_score desc, fr.global_rank, fr.user_id
limit 500;