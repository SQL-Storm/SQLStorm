with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
q_posts as (
  select p.id,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.answercount,
         p.closeddate
  from posts p
  where p.posttypeid = 1
),
a_posts as (
  select p.id,
         p.parentid,
         p.owneruserid,
         p.creationdate,
         p.score
  from posts p
  where p.posttypeid = 2
),
user_activity as (
  select ru.user_id,
         count(distinct case when qp.id is not null then qp.id end) as q_count,
         count(distinct case when ap.id is not null then ap.id end) as a_count,
         sum(coalesce(ap.score,0)) filter (where ap.id is not null) as a_score_sum,
         sum(coalesce(qp.score,0)) filter (where qp.id is not null) as q_score_sum,
         max(coalesce(qp.viewcount,0)) as max_q_views,
         min(qp.creationdate) as first_q_date,
         max(qp.creationdate) as last_q_date
  from recent_users ru
  left join q_posts qp on qp.owneruserid = ru.user_id
  left join a_posts ap on ap.owneruserid = ru.user_id
  group by ru.user_id
),
accepted_answer_lag as (
  select qp.id as question_id,
         qp.owneruserid as asker_id,
         aa.id as answer_id,
         aa.owneruserid as answerer_id,
         aa.creationdate as accepted_creationdate,
         qp.creationdate as question_creationdate,
         extract(epoch from (aa.creationdate - qp.creationdate)) as seconds_to_accept
  from q_posts qp
  join posts aa on aa.id = qp.acceptedanswerid
),
answerer_perf as (
  select ap.owneruserid as answerer_id,
         count(*) as answers_count,
         sum(case when qp.acceptedanswerid = ap.id then 1 else 0 end) as accepted_count,
         avg(ap.score) as avg_ans_score,
         percentile_cont(0.5) within group (order by ap.score) as median_ans_score,
         avg(extract(epoch from (ap.creationdate - qp.creationdate))) as avg_secs_to_answer
  from a_posts ap
  join q_posts qp on qp.id = ap.parentid
  group by ap.owneruserid
),
tag_explode as (
  select qp.id as question_id,
         unnest(string_to_array(substring(qp.tags, 2, greatest(length(qp.tags)-2,0)), '><')) as tag
  from q_posts qp
  where qp.tags is not null and qp.tags like '<%>'
),
user_tag_mix as (
  select qp.owneruserid as user_id,
         t.tag,
         count(*) as tag_q_count
  from q_posts qp
  join tag_explode t on t.question_id = qp.id
  group by qp.owneruserid, t.tag
),
top3_tags as (
  select user_id,
         (array_agg(tag order by tag_q_count desc, tag asc)) as top_tags_arr
  from user_tag_mix
  group by user_id
),
badges_roll as (
  select b.userid,
         b.class,
         b.name,
         b.date,
         sum(1) over (partition by b.userid order by b.date rows between unbounded preceding and current row) as running_badge_count
  from badges b
),
comment_stats as (
  select c.userid as user_id,
         count(*) as comments_count,
         avg(c.score) as avg_comment_score,
         sum(case when lower(c.text) like '%thanks%' or lower(c.text) like '%thank you%' then 1 else 0 end) as polite_comments
  from comments c
  where c.userid is not null
  group by c.userid
),
dup_closure as (
  select ph.postid as question_id,
         ph.creationdate as close_date,
         cast(ph.comment as integer) as close_reason_id
  from posthistory ph
  where ph.posthistorytypeid = 10
    and (ph.comment ~ '^[0-9]+$' or ph.comment is null)
),
link_dups as (
  select pl.postid as question_id,
         count(*) filter (where pl.linktypeid = 3) as dup_links_count
  from postlinks pl
  group by pl.postid
),
views_vs_votes as (
  select p.id as post_id,
         p.viewcount,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes
  from posts p
  left join votes v on v.postid = p.id
  where p.posttypeid in (1,2)
  group by p.id, p.viewcount
),
user_engagement as (
  select coalesce(q.owneruserid, a.owneruserid) as user_id,
         sum(case when q.id is not null then 1 else 0 end) as q_posts,
         sum(case when a.id is not null then 1 else 0 end) as a_posts,
         avg(vvv.upvotes - vvv.downvotes) as avg_net_votes,
         corr(cast(vvv.viewcount as double precision), cast((vvv.upvotes - vvv.downvotes) as double precision)) as corr_views_votes
  from views_vs_votes vvv
  left join q_posts q on q.id = vvv.post_id
  left join a_posts a on a.id = vvv.post_id
  group by coalesce(q.owneruserid, a.owneruserid)
),
recent_hot as (
  select qp.id,
         qp.owneruserid,
         qp.score,
         qp.viewcount,
         qp.creationdate,
         dense_rank() over (partition by date_trunc('month', qp.creationdate) order by qp.score desc, qp.viewcount desc, qp.id) as rnk_month
  from q_posts qp
  where qp.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days'
),
ranked_hot as (
  select * from recent_hot where rnk_month <= 10
),
user_last_access as (
  select u.id as user_id,
         u.lastaccessdate,
         cast('2024-10-01 12:34:56' as timestamp) - u.lastaccessdate as idle_interval
  from users u
),
final_users as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.creationdate,
         ru.location,
         ru.websiteurl_norm,
         ua.q_count,
         ua.a_count,
         ua.q_score_sum,
         ua.a_score_sum,
         ua.max_q_views,
         ua.first_q_date,
         ua.last_q_date,
         ap.answers_count,
         ap.accepted_count,
         ap.avg_ans_score,
         ap.median_ans_score,
         ap.avg_secs_to_answer,
         top3_tags.top_tags_arr as top_tags,
         cs.comments_count,
         cs.avg_comment_score,
         cs.polite_comments,
         ue.q_posts,
         ue.a_posts,
         ue.avg_net_votes,
         ue.corr_views_votes,
         ula.lastaccessdate,
         ula.idle_interval
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join answerer_perf ap on ap.answerer_id = ru.user_id
  left join top3_tags on top3_tags.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join user_engagement ue on ue.user_id = ru.user_id
  left join user_last_access ula on ula.user_id = ru.user_id
),
question_quality as (
  select qp.id as question_id,
         qp.owneruserid as user_id,
         qp.score,
         qp.viewcount,
         qp.answercount,
         qp.closeddate,
         ld.dup_links_count,
         dc.close_reason_id,
         case
           when qp.closeddate is not null then 'closed'
           when coalesce(ld.dup_links_count,0) >= 1 then 'duplicate-ish'
           when qp.score >= 5 and qp.viewcount >= 1000 then 'hot'
           when qp.score < 0 and qp.answercount = 0 then 'low-quality'
           else 'normal'
         end as quality_bucket
  from q_posts qp
  left join link_dups ld on ld.question_id = qp.id
  left join dup_closure dc on dc.question_id = qp.id
),
stringy as (
  select fu.user_id,
         upper(coalesce(nullif(fu.displayname,''), 'Anonymous')) as display_upper,
         regexp_replace(coalesce(fu.location,'unknown'), '\s+', ' ', 'g') as location_clean,
         length(coalesce(fu.websiteurl_norm,'')) as website_len,
         case
           when fu.reputation >= 100000 then 'Legend'
           when fu.reputation >= 20000 then 'Expert'
           when fu.reputation >= 5000 then 'Advanced'
           when fu.reputation >= 1000 then 'Intermediate'
           when fu.reputation >= 100 then 'Novice'
           else 'Newbie'
         end as rep_band
  from final_users fu
),
user_quality_agg as (
  select qq.user_id,
         count(*) as total_q,
         sum(case when qq.quality_bucket = 'hot' then 1 else 0 end) as hot_q,
         sum(case when qq.quality_bucket = 'low-quality' then 1 else 0 end) as low_q,
         sum(case when qq.quality_bucket = 'duplicate-ish' then 1 else 0 end) as dupish_q,
         sum(case when qq.quality_bucket = 'closed' then 1 else 0 end) as closed_q,
         avg(qq.score) as avg_q_score,
         avg(qq.viewcount) as avg_q_views
  from question_quality qq
  group by qq.user_id
),
cohort as (
  select fu.user_id,
         date_trunc('quarter', fu.creationdate) as cohort_qtr
  from final_users fu
),
cohort_stats as (
  select c.cohort_qtr,
         count(distinct fu.user_id) as users_in_cohort,
         avg(fu.reputation) as avg_rep,
         percentile_cont(0.9) within group (order by coalesce(ue.avg_net_votes,0)) as p90_net_votes
  from cohort c
  join final_users fu on fu.user_id = c.user_id
  left join user_engagement ue on ue.user_id = fu.user_id
  group by c.cohort_qtr
),
outliers as (
  select fu.user_id,
         fu.reputation,
         fu.a_score_sum + fu.q_score_sum as total_score_sum,
         case when fu.a_score_sum + fu.q_score_sum > 0
              then cast(fu.reputation as numeric) / nullif(fu.a_score_sum + fu.q_score_sum,0)
              else null end as rep_per_score
  from final_users fu
),
user_summary as (
  select fu.*,
         s.display_upper,
         s.location_clean,
         s.website_len,
         s.rep_band,
         uqa.total_q,
         uqa.hot_q,
         uqa.low_q,
         uqa.dupish_q,
         uqa.closed_q,
         uqa.avg_q_score,
         uqa.avg_q_views
  from final_users fu
  left join stringy s on s.user_id = fu.user_id
  left join user_quality_agg uqa on uqa.user_id = fu.user_id
),
cross_comparison as (
  select us1.user_id as user_id,
         us2.user_id as peer_id,
         us1.rep_band,
         us2.rep_band as peer_rep_band,
         us1.avg_net_votes - us2.avg_net_votes as diff_avg_net_votes,
         us1.a_count - us2.a_count as diff_answers,
         abs(coalesce(us1.corr_views_votes,0) - coalesce(us2.corr_views_votes,0)) as diff_corr
  from user_summary us1
  join user_summary us2
    on us1.rep_band = us2.rep_band
   and us1.user_id <> us2.user_id
  where us1.q_count + us1.a_count >= 5
    and us2.q_count + us2.a_count >= 5
),
agg_cross as (
  select user_id,
         avg(diff_avg_net_votes) as peer_avg_net_votes_gap,
         avg(diff_answers) as peer_answers_gap,
         avg(diff_corr) as peer_corr_gap
  from cross_comparison
  group by user_id
)
select
  us.user_id,
  us.displayname,
  s.rep_band,
  us.reputation,
  us.q_count,
  us.a_count,
  coalesce(uqa.total_q,0) as total_q,
  coalesce(uqa.hot_q,0) as hot_q,
  coalesce(uqa.low_q,0) as low_q,
  coalesce(uqa.closed_q,0) as closed_q,
  coalesce(uqa.avg_q_score,0) as avg_q_score,
  coalesce(uqa.avg_q_views,0) as avg_q_views,
  coalesce(us.answers_count,0) as answers_count,
  coalesce(us.accepted_count,0) as accepted_count,
  coalesce(us.avg_ans_score,0) as avg_ans_score,
  coalesce(us.median_ans_score,0) as median_ans_score,
  round(coalesce(us.avg_secs_to_answer,0), 2) as avg_secs_to_answer,
  coalesce(us.top_tags, array[]::text[]) as top_tags,
  coalesce(us.comments_count,0) as comments_count,
  coalesce(us.polite_comments,0) as polite_comments,
  round(coalesce(us.avg_comment_score,0), 2) as avg_comment_score,
  round(coalesce(us.avg_net_votes,0), 2) as avg_net_votes,
  round(coalesce(us.corr_views_votes,0), 4) as corr_views_votes,
  us.max_q_views,
  us.first_q_date,
  us.last_q_date,
  us.lastaccessdate,
  us.idle_interval,
  ac.peer_avg_net_votes_gap,
  ac.peer_answers_gap,
  ac.peer_corr_gap,
  case
    when us.websiteurl_norm is null or us.websiteurl_norm in ('', 'n/a') then null
    when position('stackoverflow' in lower(us.websiteurl_norm)) > 0 then 'so'
    when position('github' in lower(us.websiteurl_norm)) > 0 then 'gh'
    else 'other'
  end as website_bucket,
  (select count(*) from badges b where b.userid = us.user_id and b.class = 1) as gold_badges,
  (select count(*) from badges b where b.userid = us.user_id and b.class = 2) as silver_badges,
  (select count(*) from badges b where b.userid = us.user_id and b.class = 3) as bronze_badges,
  row_number() over (order by us.reputation desc, us.user_id) as rownum_global,
  rank() over (partition by s.rep_band order by us.reputation desc, us.user_id) as rank_in_band,
  case when exists (
    select 1
    from ranked_hot rh
    where rh.owneruserid = us.user_id
  ) then 1 else 0 end as has_recent_hot_q,
  coalesce(oa.answers_count,0) as overall_answers_count_check,
  (select cs.p90_net_votes from cohort_stats cs
   where cs.cohort_qtr = date_trunc('quarter', us.creationdate)) as cohort_p90_net_votes
from user_summary us
left join stringy s on s.user_id = us.user_id
left join user_quality_agg uqa on uqa.user_id = us.user_id
left join answerer_perf oa on oa.answerer_id = us.user_id
left join agg_cross ac on ac.user_id = us.user_id
where
  (coalesce(us.q_count,0) + coalesce(us.a_count,0)) >= 3
  and coalesce(us.avg_net_votes, 0) >= -5
  and (s.rep_band in ('Intermediate','Advanced','Expert','Legend')
       or (coalesce(uqa.total_q,0) >= 5 and coalesce(uqa.avg_q_views,0) >= 100))
  and not (coalesce(uqa.closed_q,0) > coalesce(uqa.total_q,0) / 2.0)
order by us.reputation desc, us.user_id
limit 200;