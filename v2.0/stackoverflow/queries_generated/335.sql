-- {"query": "335.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3718} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl,''), '/', 3)), ''), 'unknown') as domain,
           date_trunc('month', u.creationdate) as signup_month
    from users u
    where u.creationdate >= now() - interval '3 years'
),
user_activity as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           sum(coalesce(p.score,0)) as post_score,
           sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as q_views,
           sum(coalesce(p.commentcount,0)) as comments_on_posts,
           max(p.lastactivitydate) as last_post_activity,
           count(distinct p.id) as posts_count
    from posts p
    where p.owneruserid is not null
      and p.owneruserid <> -1
      and p.creationdate >= now() - interval '3 years'
    group by p.owneruserid
),
user_votes as (
    select v.userid as user_id,
           count(*) filter (where v.votetypeid = 2) as upvotes_cast,
           count(*) filter (where v.votetypeid = 3) as downvotes_cast,
           count(*) filter (where v.votetypeid = 8) as bounties_started,
           sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total,
           max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
      and v.creationdate >= now() - interval '3 years'
    group by v.userid
),
user_badges as (
    select b.userid as user_id,
           count(*) as total_badges,
           count(*) filter (where b.class = 1) as gold_badges,
           count(*) filter (where b.class = 2) as silver_badges,
           count(*) filter (where b.class = 3) as bronze_badges,
           bool_or(b.tagbased) as any_tag_badges,
           max(b.date) as last_badge_date
    from badges b
    where b.date >= now() - interval '3 years'
    group by b.userid
),
question_tags as (
    select p.id as post_id,
           unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
      and p.creationdate >= now() - interval '3 years'
),
user_tag_focus as (
    select p.owneruserid as user_id,
           qt.tag,
           count(*) as tag_posts,
           sum(coalesce(p.score,0)) as tag_score,
           row_number() over (partition by p.owneruserid order by count(*) desc, sum(coalesce(p.score,0)) desc, min(p.creationdate)) as rn
    from posts p
    join question_tags qt on qt.post_id = p.id
    group by p.owneruserid, qt.tag
),
top_user_tag as (
    select user_id,
           tag as top_tag,
           tag_posts as top_tag_posts,
           tag_score as top_tag_score
    from user_tag_focus
    where rn = 1
),
question_closures as (
    select ph.postid as question_id,
           min(ph.creationdate) as first_close_date,
           max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id,
           count(*) filter (where ph.posthistorytypeid = 10) as close_events
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
      and ph.creationdate >= now() - interval '3 years'
    group by ph.postid
),
duplicate_links as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as original_post_id,
           min(pl.creationdate) as first_link_date
    from postlinks pl
    where pl.linktypeid = 3
      and pl.creationdate >= now() - interval '3 years'
    group by pl.postid, pl.relatedpostid
),
hotness as (
    select p.id as post_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.viewcount,
           p.score,
           extract(epoch from (now() - p.creationdate)) as age_sec,
           case
               when p.viewcount is null or p.viewcount = 0 then 0
               else (p.score::numeric * 2 + coalesce(p.commentcount,0)) / greatest(extract(epoch from (now() - p.creationdate)) / 3600.0, 1)
           end as hot_score
    from posts p
    where p.creationdate >= now() - interval '2 years'
      and p.posttypeid in (1,2)
),
user_hot_agg as (
    select user_id,
           avg(hot_score) as avg_hot_score,
           max(hot_score) as peak_hot_score,
           percentile_cont(0.9) within group (order by hot_score) as p90_hot_score,
           count(*) as hot_samples
    from hotness
    where user_id is not null and user_id <> -1
    group by user_id
),
engagement as (
    select u.id as user_id,
           count(distinct c.id) as comments_made,
           sum(c.score) as comment_score,
           max(c.creationdate) as last_comment_date
    from users u
    left join comments c on c.userid = u.id
                         and c.creationdate >= now() - interval '3 years'
    where u.creationdate >= now() - interval '3 years'
    group by u.id
),
question_quality as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as q_total,
           avg(nullif(p.viewcount,0)) filter (where p.posttypeid = 1) as avg_q_views,
           avg(nullif(p.score,0)) filter (where p.posttypeid = 1) as avg_q_score,
           sum(case when qc.first_close_date is not null then 1 else 0 end) as q_closed,
           sum(case when dl.original_post_id is not null then 1 else 0 end) as q_marked_duplicate
    from posts p
    left join question_closures qc on qc.question_id = p.id
    left join duplicate_links dl on dl.dup_post_id = p.id
    where p.creationdate >= now() - interval '3 years'
      and p.owneruserid is not null and p.owneruserid <> -1
    group by p.owneruserid
),
rep_trend as (
    select u.id as user_id,
           date_trunc('month', p.creationdate) as ym,
           sum(coalesce(p.score,0)) as month_post_score,
           count(*) filter (where p.posttypeid=2 and p.score>0) as positive_answers,
           count(*) filter (where p.posttypeid=1 and p.score>0) as positive_questions
    from users u
    left join posts p on p.owneruserid = u.id
                     and p.creationdate >= now() - interval '2 years'
    where u.creationdate >= now() - interval '3 years'
    group by u.id, date_trunc('month', p.creationdate)
),
rep_trend_rank as (
    select user_id,
           ym,
           month_post_score,
           sum(coalesce(month_post_score,0)) over (partition by user_id order by ym rows between 11 preceding and current row) as rolling_12m_score,
           row_number() over (partition by user_id order by coalesce(month_post_score, -999999) desc, ym) as best_month_rank
    from rep_trend
),
domain_activity as (
    select ru.domain,
           count(distinct ru.user_id) as domain_users,
           sum(coalesce(ua.posts_count,0)) as domain_posts,
           sum(coalesce(ua.q_count,0)) as domain_qs,
           sum(coalesce(ua.a_count,0)) as domain_as
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    group by ru.domain
),
user_flags as (
    select u.id as user_id,
           case when coalesce(ua.posts_count,0) = 0 and coalesce(e.comments_made,0) = 0 then 1 else 0 end as lurker_flag,
           case when qq.q_closed > 0 then 1 else 0 end as closerisk_flag,
           case when coalesce(ua.a_count,0) > coalesce(ua.q_count,0) * 3 then 1 else 0 end as heavy_answerer_flag
    from users u
    left join user_activity ua on ua.user_id = u.id
    left join engagement e on e.user_id = u.id
    left join question_quality qq on qq.user_id = u.id
),
final_users as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.signup_month,
           ru.domain,
           coalesce(ua.q_count,0) as q_count,
           coalesce(ua.a_count,0) as a_count,
           coalesce(ua.post_score,0) as post_score,
           coalesce(ua.q_views,0) as q_views,
           ua.last_post_activity,
           coalesce(uv.upvotes_cast,0) as upvotes_cast,
           coalesce(uv.downvotes_cast,0) as downvotes_cast,
           coalesce(uv.bounties_started,0) as bounties_started,
           coalesce(uv.bounty_amount_total,0) as bounty_amount_total,
           uv.last_vote_date,
           coalesce(ub.total_badges,0) as total_badges,
           coalesce(ub.gold_badges,0) as gold_badges,
           coalesce(ub.silver_badges,0) as silver_badges,
           coalesce(ub.bronze_badges,0) as bronze_badges,
           ub.any_tag_badges,
           ub.last_badge_date,
           tut.top_tag,
           tut.top_tag_posts,
           tut.top_tag_score,
           coalesce(qa.q_total,0) as q_total,
           qa.avg_q_views,
           qa.avg_q_score,
           coalesce(qa.q_closed,0) as q_closed,
           coalesce(qa.q_marked_duplicate,0) as q_marked_duplicate,
           coalesce(uh.avg_hot_score,0) as avg_hot_score,
           coalesce(uh.peak_hot_score,0) as peak_hot_score,
           coalesce(uh.p90_hot_score,0) as p90_hot_score,
           coalesce(uh.hot_samples,0) as hot_samples,
           coalesce(e.comments_made,0) as comments_made,
           coalesce(e.comment_score,0) as comment_score,
           e.last_comment_date,
           max(case when rtr.best_month_rank = 1 then rtr.month_post_score end) as best_month_score,
           max(rtr.rolling_12m_score) as rolling_12m_score,
           uf.lurker_flag,
           uf.closerisk_flag,
           uf.heavy_answerer_flag
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_votes uv on uv.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join top_user_tag tut on tut.user_id = ru.user_id
    left join question_quality qa on qa.user_id = ru.user_id
    left join user_hot_agg uh on uh.user_id = ru.user_id
    left join engagement e on e.user_id = ru.user_id
    left join rep_trend_rank rtr on rtr.user_id = ru.user_id
    left join user_flags uf on uf.user_id = ru.user_id
    group by ru.user_id, ru.displayname, ru.reputation, ru.signup_month, ru.domain,
             ua.q_count, ua.a_count, ua.post_score, ua.q_views, ua.last_post_activity,
             uv.upvotes_cast, uv.downvotes_cast, uv.bounties_started, uv.bounty_amount_total, uv.last_vote_date,
             ub.total_badges, ub.gold_badges, ub.silver_badges, ub.bronze_badges, ub.any_tag_badges, ub.last_badge_date,
             tut.top_tag, tut.top_tag_posts, tut.top_tag_score,
             qa.q_total, qa.avg_q_views, qa.avg_q_score, qa.q_closed, qa.q_marked_duplicate,
             uh.avg_hot_score, uh.peak_hot_score, uh.p90_hot_score, uh.hot_samples,
             e.comments_made, e.comment_score, e.last_comment_date,
             uf.lurker_flag, uf.closerisk_flag, uf.heavy_answerer_flag
),
domain_ranks as (
    select fu.*,
           rank() over (partition by fu.domain order by coalesce(fu.post_score,0) desc) as domain_postscore_rank,
           rank() over (partition by fu.domain order by coalesce(fu.total_badges,0) desc) as domain_badge_rank,
           rank() over (partition by fu.domain order by coalesce(fu.avg_hot_score,0) desc) as domain_hot_rank
    from final_users fu
),
topk as (
    select *
    from domain_ranks
    where domain_postscore_rank <= 50
       or domain_badge_rank <= 50
       or domain_hot_rank <= 50
),
dup_risk as (
    select p.owneruserid as user_id,
           count(*) as duplicates_authored,
           sum(case when ph.posthistorytypeid = 10 and try_cast(ph.comment as int) = 101 then 1 else 0 end) as duplicate_closes
    from posts p
    left join posthistory ph on ph.postid = p.id and ph.posthistorytypeid = 10
    left join postlinks pl on pl.postid = p.id and pl.linktypeid = 3
    where p.posttypeid = 1
      and (pl.id is not null or ph.id is not null)
      and p.creationdate >= now() - interval '3 years'
    group by p.owneruserid
)
select tk.user_id,
       tk.displayname,
       tk.reputation,
       tk.signup_month,
       tk.domain,
       tk.q_count,
       tk.a_count,
       tk.post_score,
       tk.q_views,
       tk.last_post_activity,
       tk.upvotes_cast,
       tk.downvotes_cast,
       tk.bounties_started,
       tk.bounty_amount_total,
       tk.last_vote_date,
       tk.total_badges,
       tk.gold_badges,
       tk.silver_badges,
       tk.bronze_badges,
       tk.any_tag_badges,
       tk.last_badge_date,
       tk.top_tag,
       tk.top_tag_posts,
       tk.top_tag_score,
       tk.q_total,
       tk.avg_q_views,
       tk.avg_q_score,
       tk.q_closed,
       tk.q_marked_duplicate,
       tk.avg_hot_score,
       tk.peak_hot_score,
       tk.p90_hot_score,
       tk.hot_samples,
       tk.comments_made,
       tk.comment_score,
       tk.last_comment_date,
       tk.best_month_score,
       tk.rolling_12m_score,
       tk.lurker_flag,
       tk.closerisk_flag,
       tk.heavy_answerer_flag,
       tk.domain_postscore_rank,
       tk.domain_badge_rank,
       tk.domain_hot_rank,
       coalesce(dr.duplicates_authored,0) as duplicates_authored,
       coalesce(dr.duplicate_closes,0) as duplicate_closes,
       case
         when coalesce(tk.q_total,0) = 0 then null
         else round(100.0 * coalesce(tk.q_marked_duplicate,0) / greatest(tk.q_total,1), 2)
       end as dup_rate_pct,
       case
         when tk.upvotes_cast + tk.downvotes_cast = 0 then null
         else round(100.0 * tk.upvotes_cast::numeric / (tk.upvotes_cast + tk.downvotes_cast), 2)
       end as upvote_ratio_pct,
       case
         when tk.total_badges = 0 then 'None'
         when tk.gold_badges > 0 then 'Gold+'
         when tk.silver_badges > 0 then 'Silver+'
         else 'Bronze'
       end as badge_tier,
       case
         when tk.avg_hot_score > coalesce(avg(tk.avg_hot_score) over (), 0) then 1 else 0
       end as above_avg_hot_flag
from topk tk
left join dup_risk dr on dr.user_id = tk.user_id
where coalesce(tk.post_score,0) + coalesce(tk.total_badges,0) + coalesce(tk.avg_hot_score,0) > 0
order by tk.domain, tk.domain_postscore_rank, tk.user_id
limit 1000;