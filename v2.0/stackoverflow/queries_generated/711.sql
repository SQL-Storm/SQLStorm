-- {"query": "711.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3552} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
         u.websiteurl,
         date_trunc('month', u.creationdate) as cohort_month,
         count(*) over () as total_users_sample
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from users)
),
question_posts as (
  select p.id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.answercount,
         p.closeddate,
         p.contentlicense,
         p.acceptedanswerid
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select p.id,
         p.parentid as question_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score
  from posts p
  where p.posttypeid = 2
),
user_activity as (
  select ru.user_id,
         count(distinct qp.id) as questions_asked,
         sum(case when qp.closeddate is not null then 1 else 0 end) as questions_closed,
         count(distinct ap.id) as answers_posted,
         sum(coalesce(qp.viewcount,0)) as total_question_views,
         sum(coalesce(qp.score,0)) + sum(coalesce(ap.score,0)) as net_post_score,
         max(coalesce(qp.creationdate, ap.creationdate)) as last_post_date
  from recent_users ru
  left join question_posts qp on qp.user_id = ru.user_id
  left join answer_posts ap on ap.user_id = ru.user_id
  group by ru.user_id
),
votes_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  where v.creationdate >= (select min(creationdate) from recent_users ru2 join users u2 on u2.id = ru2.user_id)
  group by v.postid
),
question_enriched as (
  select qp.*,
         va.upvotes,
         va.downvotes,
         va.favorites,
         va.bounty_total,
         case when qp.acceptedanswerid is not null then 1 else 0 end as has_accepted_answer,
         cardinality(string_to_array(coalesce(substring(qp.tags, 2, length(qp.tags)-2), ''), '><')) as tag_count
  from question_posts qp
  left join votes_agg va on va.postid = qp.id
),
dup_links as (
  select pl.postid as dup_post_id,
         pl.relatedpostid as canonical_post_id
  from postlinks pl
  where pl.linktypeid = 3
),
close_events as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid = 10) as close_votes,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_close_vote_at,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_at,
         max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_raw
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
tag_expansion as (
  select qe.id as question_id,
         unnest(string_to_array(substring(qe.tags, 2, greatest(length(qe.tags)-2,0)), '><')) as tagname
  from question_enriched qe
  where qe.tags is not null and qe.tags like '<%>'
),
hotness as (
  select qe.id as question_id,
         0.4 * coalesce(qe.upvotes,0) - 0.6 * coalesce(qe.downvotes,0) +
         0.001 * coalesce(qe.viewcount,0) +
         15 * qe.has_accepted_answer +
         3 * coalesce(qe.favorites,0) +
         0.02 * coalesce(qe.bounty_total,0) -
         2 * coalesce(ce.close_votes,0) +
         1.5 * least(coalesce(qe.tag_count,0), 5) +
         case when dl.canonical_post_id is not null then -25 else 0 end as hot_score,
         row_number() over (order by
           (0.4 * coalesce(qe.upvotes,0) - 0.6 * coalesce(qe.downvotes,0) +
            0.001 * coalesce(qe.viewcount,0) + 15 * qe.has_accepted_answer +
            3 * coalesce(qe.favorites,0) + 0.02 * coalesce(qe.bounty_total,0) -
            2 * coalesce(ce.close_votes,0) + 1.5 * least(coalesce(qe.tag_count,0), 5) +
            case when dl.canonical_post_id is not null then -25 else 0 end) desc,
           qe.creationdate desc) as hot_rank
  from question_enriched qe
  left join close_events ce on ce.postid = qe.id
  left join dup_links dl on dl.dup_post_id = qe.id
),
user_engagement as (
  select ru.user_id,
         sum(case when ap.id is not null then 1 else 0 end) as answers_in_window,
         count(distinct case when qe.id is not null then qe.id end) as questions_in_window,
         avg(case when ap.id is not null then ap.score end) as avg_answer_score,
         avg(case when qe.id is not null then qe.score end) as avg_question_score,
         max(qe.creationdate) as last_question_date,
         max(ap.creationdate) as last_answer_date
  from recent_users ru
  left join answer_posts ap on ap.user_id = ru.user_id and ap.creationdate >= ru.creationdate
  left join question_enriched qe on qe.owneruserid = ru.user_id and qe.creationdate >= ru.creationdate
  group by ru.user_id
),
comment_agg as (
  select c.userid as user_id,
         count(*) as comments_made,
         sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
         max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
badge_agg as (
  select b.userid as user_id,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
tag_popularity as (
  select te.tagname,
         count(*) as tag_usage_count,
         avg(qe.score) as avg_score_per_tag
  from tag_expansion te
  join question_enriched qe on qe.id = te.question_id
  group by te.tagname
),
location_stats as (
  select ru.location_norm,
         count(*) as user_count,
         avg(ru.reputation) as avg_rep
  from recent_users ru
  group by ru.location_norm
),
power_users as (
  select ua.user_id,
         ua.questions_asked,
         ua.answers_posted,
         ua.net_post_score,
         ue.answers_in_window,
         ue.questions_in_window,
         coalesce(ba.gold_badges,0) + coalesce(ba.silver_badges,0) + coalesce(ba.bronze_badges,0) as total_badges,
         coalesce(ca.comments_made,0) as comments_made,
         dense_rank() over (order by
            (ua.net_post_score * 2 + ua.answers_posted * 5 + ua.questions_asked * 3 +
             coalesce(ba.gold_badges,0) * 50 + coalesce(ba.silver_badges,0) * 10 + coalesce(ba.bronze_badges,0) * 2 +
             coalesce(ca.comments_made,0) * 0.2) desc) as influence_rank
  from user_activity ua
  left join user_engagement ue on ue.user_id = ua.user_id
  left join badge_agg ba on ba.user_id = ua.user_id
  left join comment_agg ca on ca.user_id = ua.user_id
),
question_quality as (
  select qe.id as question_id,
         qe.owneruserid as user_id,
         qe.score,
         qe.viewcount,
         qe.has_accepted_answer,
         coalesce(va.upvotes,0) as upvotes,
         coalesce(va.downvotes,0) as downvotes,
         coalesce(ce.close_votes,0) as close_votes,
         case
           when qe.score >= 10 and qe.has_accepted_answer = 1 and coalesce(ce.close_votes,0) = 0 then 'Excellent'
           when qe.score >= 3 and qe.has_accepted_answer = 1 then 'Good'
           when qe.score < 0 or coalesce(ce.close_votes,0) > 0 then 'Poor'
           else 'Average'
         end as quality_band
  from question_enriched qe
  left join votes_agg va on va.postid = qe.id
  left join close_events ce on ce.postid = qe.id
),
top_tags as (
  select tp.tagname,
         tp.tag_usage_count,
         tp.avg_score_per_tag,
         ntile(4) over (order by tp.tag_usage_count desc) as popularity_quartile
  from tag_popularity tp
),
user_tag_pref as (
  select qe.owneruserid as user_id,
         te.tagname,
         count(*) as uses,
         avg(qe.score) as avg_score,
         rank() over (partition by qe.owneruserid order by count(*) desc, avg(qe.score) desc) as tag_rank
  from question_enriched qe
  join tag_expansion te on te.question_id = qe.id
  group by qe.owneruserid, te.tagname
),
cross_user_similarity as (
  select ut1.user_id as user_a,
         ut2.user_id as user_b,
         sum(least(ut1.uses, ut2.uses)) as overlap_weight
  from user_tag_pref ut1
  join user_tag_pref ut2
    on ut1.tagname = ut2.tagname
   and ut1.user_id < ut2.user_id
   and ut1.tag_rank <= 10
   and ut2.tag_rank <= 10
  group by ut1.user_id, ut2.user_id
  having sum(least(ut1.uses, ut2.uses)) >= 3
),
question_lifecycle as (
  select qe.id as question_id,
         qe.creationdate,
         first_value(ph.creationdate) filter (where ph.posthistorytypeid = 10) over (partition by qe.id order by ph.creationdate rows between unbounded preceding and unbounded following) as first_close_at,
         first_value(ph.creationdate) filter (where ph.posthistorytypeid = 11) over (partition by qe.id order by ph.creationdate rows between unbounded preceding and unbounded following) as first_reopen_at
  from question_enriched qe
  left join posthistory ph on ph.postid = qe.id and ph.posthistorytypeid in (10,11)
),
final_scores as (
  select ru.user_id,
         ru.displayname,
         ru.location_norm,
         ru.cohort_month,
         pu.influence_rank,
         ua.questions_asked,
         ua.answers_posted,
         ua.net_post_score,
         ue.avg_answer_score,
         ue.avg_question_score,
         coalesce(ba.gold_badges,0) as gold_badges,
         coalesce(ba.silver_badges,0) as silver_badges,
         coalesce(ba.bronze_badges,0) as bronze_badges,
         coalesce(ca.comments_made,0) as comments_made,
         count(distinct qq.question_id) filter (where qq.quality_band = 'Excellent') as excellent_questions,
         count(distinct qq.question_id) filter (where qq.quality_band = 'Poor') as poor_questions,
         avg(h.hot_score) as avg_hot_score,
         percentile_cont(0.9) within group (order by h.hot_score) as p90_hot_score,
         count(distinct qs.question_id) as questions_with_lifecycle,
         count(distinct case when st.popularity_quartile = 1 then te.tagname end) as top_quartile_tags_used
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join user_engagement ue on ue.user_id = ru.user_id
  left join badge_agg ba on ba.user_id = ru.user_id
  left join comment_agg ca on ca.user_id = ru.user_id
  left join power_users pu on pu.user_id = ru.user_id
  left join question_enriched qe on qe.owneruserid = ru.user_id
  left join hotness h on h.question_id = qe.id
  left join question_quality qq on qq.user_id = ru.user_id and qq.question_id = qe.id
  left join question_lifecycle qs on qs.question_id = qe.id
  left join tag_expansion te on te.question_id = qe.id
  left join top_tags st on st.tagname = te.tagname
  group by ru.user_id, ru.displayname, ru.location_norm, ru.cohort_month, pu.influence_rank,
           ua.questions_asked, ua.answers_posted, ua.net_post_score, ue.avg_answer_score, ue.avg_question_score,
           ba.gold_badges, ba.silver_badges, ba.bronze_badges, ca.comments_made
),
ranked_final as (
  select fs.*,
         row_number() over (order by
            (coalesce(fs.avg_hot_score,0) * 1.5 +
             coalesce(fs.net_post_score,0) * 1.2 +
             coalesce(fs.excellent_questions,0) * 10 -
             coalesce(fs.poor_questions,0) * 5 +
             coalesce(fs.gold_badges,0) * 30 +
             coalesce(fs.silver_badges,0) * 8 +
             coalesce(fs.bronze_badges,0) * 2 +
             coalesce(fs.comments_made,0) * 0.05) desc,
             fs.influence_rank asc,
             fs.user_id asc) as overall_rank
  from final_scores fs
)
select rf.user_id,
       rf.displayname,
       rf.location_norm,
       rf.cohort_month,
       rf.overall_rank,
       rf.influence_rank,
       rf.questions_asked,
       rf.answers_posted,
       rf.net_post_score,
       rf.avg_answer_score,
       rf.avg_question_score,
       rf.gold_badges,
       rf.silver_badges,
       rf.bronze_badges,
       rf.comments_made,
       rf.excellent_questions,
       rf.poor_questions,
       rf.avg_hot_score,
       rf.p90_hot_score,
       rf.questions_with_lifecycle,
       rf.top_quartile_tags_used,
       case when rf.location_norm ilike '%remote%' or rf.websiteurl ilike '%github%' then 'High Online Presence'
            when rf.location_norm = 'Unknown' then 'Unknown Presence'
            else 'Normal Presence' end as presence_flag,
       to_char(rf.cohort_month, 'YYYY-MM') as cohort_str
from ranked_final rf
where (rf.excellent_questions > 0 or rf.avg_hot_score > (
         select avg(h2.hot_score)
         from hotness h2
       ))
  and rf.overall_rank <= 500
order by rf.overall_rank, rf.user_id;