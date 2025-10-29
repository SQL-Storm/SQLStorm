with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'n/a') as domain_guess
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as total_post_score,
        avg(nullif(p.viewcount,0)) as avg_views_nonzero,
        max(p.creationdate) as last_post_date,
        count(*) filter (where p.closeddate is not null) as closed_count,
        count(*) filter (where p.communityowneddate is not null) as cw_count
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(c.score) as comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
badge_stats as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_count,
        count(*) filter (where b.class = 2) as silver_count,
        count(*) filter (where b.class = 3) as bronze_count,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
post_quality as (
    select
        p.owneruserid as user_id,
        percentile_disc(0.5) within group (order by p.score) as median_post_score,
        percentile_cont(0.9) within group (order by coalesce(p.viewcount,0)) as p90_views,
        avg(length(coalesce(p.body,''))) as avg_body_len,
        avg(coalesce(p.commentcount,0)) as avg_comment_count
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
accepted_answer_ratio as (
    select
        a.owneruserid as user_id,
        cast(count(*) as numeric) as answers_total,
        cast(sum(case when q.acceptedanswerid = a.id then 1 else 0 end) as numeric) as answers_accepted,
        case when count(*) > 0 then cast(sum(case when q.acceptedanswerid = a.id then 1 else 0 end) as numeric) / cast(count(*) as numeric) else null end as accept_rate
    from posts a
    join posts q on q.id = a.parentid and a.posttypeid = 2 and q.posttypeid = 1
    group by a.owneruserid
),
tag_influence as (
    select
        p.owneruserid as user_id,
        unnest(string_to_array(substring(coalesce(p.tags,''), 2, greatest(length(coalesce(p.tags,'')) - 2, 0)), '><')) as tag
    from posts p
    where p.posttypeid = 1 and p.owneruserid is not null and p.tags is not null
),
top_tags as (
    select user_id,
           tag,
           count(*) as tag_uses,
           row_number() over (partition by user_id order by count(*) desc, tag asc) as rn
    from tag_influence
    group by user_id, tag
),
dup_activity as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.creationdate,
        pl.linktypeid,
        case when pl.linktypeid = 3 then 1 else 0 end as is_dup
    from postlinks pl
    where pl.linktypeid in (1,3)
),
close_reasons as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_date,
        max(ph.creationdate) as last_close_date,
        cast(max(nullif(regexp_replace(coalesce(ph.comment,''), '[^0-9]', '', 'g'), '')) as integer) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid = 10
    group by ph.postid
),
votes_rollup as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 5) as favorites,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
    from votes v
    group by v.postid
),
recent_q as (
    select
        p.id,
        p.owneruserid as user_id,
        p.creationdate,
        p.viewcount,
        p.score,
        p.answercount,
        p.title,
        p.tags,
        v.upvotes,
        v.downvotes,
        v.favorites,
        v.bounty_total,
        cr.last_close_reason_id,
        d.is_dup
    from posts p
    left join votes_rollup v on v.postid = p.id
    left join close_reasons cr on cr.postid = p.id
    left join dup_activity d on d.postid = p.id and d.is_dup = 1
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '90 days' from posts)
),
user_scored as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.domain_guess,
        coalesce(ua.q_count,0) as q_count,
        coalesce(ua.a_count,0) as a_count,
        coalesce(ua.total_post_score,0) as total_post_score,
        ua.avg_views_nonzero,
        ua.last_post_date,
        ua.closed_count,
        ua.cw_count,
        coalesce(cs.comment_count,0) as comment_count,
        coalesce(cs.comment_score,0) as comment_score,
        cs.last_comment_date,
        coalesce(bs.badge_count,0) as badge_count,
        coalesce(bs.gold_count,0) as gold_count,
        coalesce(bs.silver_count,0) as silver_count,
        coalesce(bs.bronze_count,0) as bronze_count,
        bs.first_badge_date,
        bs.last_badge_date,
        pq.median_post_score,
        pq.p90_views,
        pq.avg_body_len,
        pq.avg_comment_count,
        aar.accept_rate,
        coalesce(aar.answers_total,0) as answers_total,
        coalesce(aar.answers_accepted,0) as answers_accepted
    from recent_users u
    left join user_activity ua on ua.user_id = u.user_id
    left join comment_stats cs on cs.user_id = u.user_id
    left join badge_stats bs on bs.user_id = u.user_id
    left join post_quality pq on pq.user_id = u.user_id
    left join accepted_answer_ratio aar on aar.user_id = u.user_id
),
ranked as (
    select
        us.*,
        coalesce(us.accept_rate, 0) as accept_rate_nz,
        case
            when us.reputation <= 1 then 0
            else least(1.0, log(1 + greatest(us.total_post_score,0)) / log(1000))
        end as score_component_posts,
        case
            when coalesce(us.q_count,0) + coalesce(us.a_count,0) = 0 then 0
            else least(1.0, (coalesce(us.p90_views,0) / 10000.0))
        end as score_component_views,
        case
            when coalesce(us.comment_count,0) = 0 then 0
            else greatest(0, 1 - (coalesce(us.comment_score,0) / nullif(us.comment_count,0)) * 0.1)
        end as score_component_comments,
        case
            when coalesce(us.badge_count,0) = 0 then 0
            else least(1.0, (us.gold_count*3 + us.silver_count*2 + us.bronze_count*1) / 50.0)
        end as score_component_badges
    from user_scored us
),
final_scores as (
    select
        r.*,
        (
            0.35 * r.score_component_posts +
            0.25 * r.score_component_views +
            0.20 * r.score_component_comments +
            0.20 * r.score_component_badges +
            0.15 * r.accept_rate_nz
        ) as composite_score,
        row_number() over (order by (
            0.35 * r.score_component_posts +
            0.25 * r.score_component_views +
            0.20 * r.score_component_comments +
            0.20 * r.score_component_badges +
            0.15 * r.accept_rate_nz
        ) desc, r.reputation desc, r.user_id) as rn
    from ranked r
),
recent_q_aggs as (
    select
        rq.user_id,
        count(*) as recent_q_count,
        avg(rq.score) as recent_q_avg_score,
        avg(rq.viewcount) as recent_q_avg_views,
        count(*) filter (where rq.last_close_reason_id is not null) as recent_q_closed,
        count(*) filter (where rq.is_dup = 1) as recent_q_marked_duplicate,
        max(rq.creationdate) as most_recent_q
    from recent_q rq
    group by rq.user_id
),
top3_tags as (
    select user_id,
           string_agg(tag || ':' || cast(tag_uses as text), ', ' order by rn) as top3
    from top_tags
    where rn <= 3
    group by user_id
),
null_guard as (
    select
        fs.user_id,
        fs.displayname,
        fs.reputation,
        fs.creationdate,
        coalesce(nullif(fs.location,''), 'Unknown') as location,
        coalesce(nullif(fs.domain_guess,''), 'Unknown') as domain_guess,
        coalesce(fs.q_count,0) as q_count,
        coalesce(fs.a_count,0) as a_count,
        coalesce(fs.total_post_score,0) as total_post_score,
        coalesce(fs.avg_views_nonzero,0) as avg_views_nonzero,
        fs.last_post_date,
        coalesce(fs.closed_count,0) as closed_count,
        coalesce(fs.cw_count,0) as cw_count,
        coalesce(fs.comment_count,0) as comment_count,
        coalesce(fs.comment_score,0) as comment_score,
        fs.last_comment_date,
        coalesce(fs.badge_count,0) as badge_count,
        coalesce(fs.gold_count,0) as gold_count,
        coalesce(fs.silver_count,0) as silver_count,
        coalesce(fs.bronze_count,0) as bronze_count,
        fs.first_badge_date,
        fs.last_badge_date,
        coalesce(fs.median_post_score,0) as median_post_score,
        coalesce(fs.p90_views,0) as p90_views,
        coalesce(fs.avg_body_len,0) as avg_body_len,
        coalesce(fs.avg_comment_count,0) as avg_comment_count,
        coalesce(fs.accept_rate,0) as accept_rate,
        fs.answers_total,
        fs.answers_accepted,
        fs.composite_score,
        fs.rn
    from final_scores fs
)
select
    ng.user_id,
    ng.displayname,
    ng.reputation,
    ng.location,
    ng.domain_guess,
    ng.q_count,
    ng.a_count,
    ng.total_post_score,
    round(cast(ng.avg_views_nonzero as numeric), 2) as avg_views_nonzero,
    ng.closed_count,
    ng.cw_count,
    ng.comment_count,
    ng.comment_score,
    ng.badge_count,
    ng.gold_count,
    ng.silver_count,
    ng.bronze_count,
    round(cast(ng.median_post_score as numeric), 2) as median_post_score,
    round(cast(ng.p90_views as numeric), 2) as p90_views,
    round(cast(ng.avg_body_len as numeric), 2) as avg_body_len,
    round(cast(ng.avg_comment_count as numeric), 2) as avg_comment_count,
    round(cast(ng.accept_rate as numeric), 3) as accept_rate,
    coalesce(rqa.recent_q_count,0) as recent_q_count,
    round(cast(coalesce(rqa.recent_q_avg_score,0) as numeric), 2) as recent_q_avg_score,
    round(cast(coalesce(rqa.recent_q_avg_views,0) as numeric), 2) as recent_q_avg_views,
    coalesce(rqa.recent_q_closed,0) as recent_q_closed,
    coalesce(rqa.recent_q_marked_duplicate,0) as recent_q_marked_duplicate,
    tt.top3 as top_tags,
    round(cast(ng.composite_score as numeric), 4) as composite_score,
    dense_rank() over (order by ng.composite_score desc, ng.reputation desc) as dense_rank_overall,
    case when ng.badge_count > 0 then 'Yes' else 'No' end as has_badges,
    case when ng.comment_score < 0 then 'Toxic-ish' when ng.comment_score = 0 then 'Neutral' else 'Positive' end as comment_mood,
    case when ng.reputation >= 100000 then 'Legend'
         when ng.reputation >= 50000 then 'Guru'
         when ng.reputation >= 10000 then 'Expert'
         when ng.reputation >= 2000 then 'Pro'
         else 'Rising' end as tier
from null_guard ng
left join recent_q_aggs rqa on rqa.user_id = ng.user_id
left join top3_tags tt on tt.user_id = ng.user_id
where (ng.q_count + ng.a_count) > 0
  and (ng.badge_count > 0 or ng.accept_rate > 0.1 or coalesce(rqa.recent_q_count,0) > 0)
order by ng.composite_score desc, ng.reputation desc, ng.user_id
limit 200;