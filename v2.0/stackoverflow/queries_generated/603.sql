-- {"query": "603.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3413} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nullif(trim(u.location), ''), '(unknown)') as location_norm,
        date_trunc('month', u.creationdate) as signup_month,
        row_number() over (partition by coalesce(nullif(trim(u.location), ''), '(unknown)') order by u.reputation desc, u.id) as rn_loc_rep
    from users u
    where u.creationdate >= now() - interval '5 years'
),
posts_enriched as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        case when p.posttypeid = 1 then 1 else 0 end as is_question,
        case when p.posttypeid = 2 then 1 else 0 end as is_answer,
        string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><') as tag_list
    from posts p
    where p.creationdate >= (select min(creationdate) from recent_users)
),
user_post_rollup as (
    select
        u.user_id,
        u.displayname,
        u.location_norm,
        u.signup_month,
        count(*) filter (where pe.is_question = 1) as q_count,
        count(*) filter (where pe.is_answer = 1) as a_count,
        sum(pe.score) as total_post_score,
        avg(pe.score)::numeric(18,4) as avg_post_score,
        percentile_cont(0.5) within group (order by pe.score) as median_post_score,
        max(pe.viewcount) as max_views,
        min(pe.creationdate) as first_post_date,
        max(pe.creationdate) as last_post_date
    from recent_users u
    left join posts_enriched pe
      on pe.owneruserid = u.user_id
    group by u.user_id, u.displayname, u.location_norm, u.signup_month
),
tag_activity as (
    select
        pe.owneruserid as user_id,
        lower(t) as tag_name,
        count(*) as tag_posts,
        sum(pe.score) as tag_score,
        avg(pe.score)::numeric(18,4) as tag_avg_score,
        row_number() over (partition by pe.owneruserid order by count(*) desc, sum(pe.score) desc, lower(t)) as tag_rank_by_freq,
        row_number() over (partition by pe.owneruserid order by avg(pe.score) desc nulls last, count(*) desc, lower(t)) as tag_rank_by_avgscore
    from posts_enriched pe
    cross join lateral unnest(coalesce(pe.tag_list, array[]::varchar[])) as t
    where pe.owneruserid is not null
    group by pe.owneruserid, lower(t)
),
top_user_tag as (
    select ta.user_id,
           ta.tag_name,
           ta.tag_posts,
           ta.tag_score,
           ta.tag_avg_score
    from tag_activity ta
    where ta.tag_rank_by_freq = 1
),
votes_rollup as (
    select
        p.owneruserid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_received,
        count(*) filter (where v.votetypeid = 3) as downvotes_received,
        count(*) filter (where v.votetypeid = 8) as bounties_started_on_user_posts,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total_amount
    from posts p
    left join votes v
      on v.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_stats as (
    select
        p.owneruserid as user_id,
        count(c.id) as comments_on_user_posts,
        avg(c.score)::numeric(18,4) as avg_comment_score_on_user_posts,
        max(c.creationdate) as last_comment_date_on_user_posts
    from posts p
    left join comments c
      on c.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_date,
        count(*) as close_events_count,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events_count,
        sum(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+' then 1 else 0 end) as close_reason_counted
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
post_links_summary as (
    select
        p.owneruserid as user_id,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        count(*) filter (where pl.linktypeid = 3 and pl.postid = p.id) as as_duplicate_count,
        count(*) filter (where pl.linktypeid = 3 and pl.relatedpostid = p.id) as original_of_duplicate_count
    from posts p
    left join postlinks pl
      on (pl.postid = p.id or pl.relatedpostid = p.id)
    where p.owneruserid is not null
    group by p.owneruserid
),
badge_rollup as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_count,
        count(*) filter (where b.class = 2) as silver_count,
        count(*) filter (where b.class = 3) as bronze_count,
        count(*) filter (where b.tagbased = 1) as tag_badge_count,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_answer_delta as (
    select
        pe.owneruserid as user_id,
        count(*) filter (where pe.is_question = 1 and pe.score > 0) as pos_q,
        count(*) filter (where pe.is_question = 1 and pe.score <= 0) as nonpos_q,
        count(*) filter (where pe.is_answer = 1 and pe.score > 0) as pos_a,
        count(*) filter (where pe.is_answer = 1 and pe.score <= 0) as nonpos_a
    from posts_enriched pe
    where pe.owneruserid is not null
    group by pe.owneruserid
),
ranked_users as (
    select
        upr.*,
        coalesce(vr.upvotes_received,0) - coalesce(vr.downvotes_received,0) as net_votes_received,
        coalesce(vr.bounties_started_on_user_posts,0) as bounties_started_on_user_posts,
        coalesce(vr.bounty_total_amount,0) as bounty_total_amount,
        coalesce(cs.comments_on_user_posts,0) as comments_on_user_posts,
        cs.avg_comment_score_on_user_posts,
        cs.last_comment_date_on_user_posts,
        coalesce(pls.linked_count,0) as linkouts,
        coalesce(pls.as_duplicate_count,0) as duped_as_duplicate,
        coalesce(pls.original_of_duplicate_count,0) as duped_original,
        coalesce(br.badge_count,0) as badges_total,
        coalesce(br.gold_count,0) as gold_badges,
        coalesce(br.silver_count,0) as silver_badges,
        coalesce(br.bronze_count,0) as bronze_badges,
        coalesce(br.tag_badge_count,0) as tag_badges,
        br.first_badge_date,
        br.last_badge_date,
        tud.tag_name as top_tag,
        tud.tag_posts as top_tag_posts,
        tud.tag_score as top_tag_score,
        tud.tag_avg_score as top_tag_avg_score,
        qad.pos_q, qad.nonpos_q, qad.pos_a, qad.nonpos_a,
        case
            when upr.a_count = 0 then null
            else (upr.q_count::numeric / nullif(upr.a_count,0))::numeric(18,4)
        end as q_to_a_ratio,
        case when upr.q_count + upr.a_count > 0 then
            (upr.total_post_score::numeric / nullif(upr.q_count + upr.a_count, 0))::numeric(18,4)
        else null end as score_per_post,
        case when coalesce(vr.upvotes_received,0) + coalesce(vr.downvotes_received,0) > 0 then
            (coalesce(vr.upvotes_received,0)::numeric / nullif(coalesce(vr.upvotes_received,0) + coalesce(vr.downvotes_received,0),0))::numeric(18,4)
        else null end as upvote_ratio,
        row_number() over (
            partition by upr.location_norm
            order by coalesce(vr.upvotes_received,0) - coalesce(vr.downvotes_received,0) desc,
                     upr.total_post_score desc,
                     coalesce(br.badge_count,0) desc,
                     upr.user_id
        ) as rank_in_location,
        dense_rank() over (
            order by coalesce(vr.upvotes_received,0) - coalesce(vr.downvotes_received,0) desc,
                     upr.total_post_score desc,
                     coalesce(br.badge_count,0) desc,
                     upr.user_id
        ) as global_rank
    from user_post_rollup upr
    left join votes_rollup vr on vr.user_id = upr.user_id
    left join comment_stats cs on cs.user_id = upr.user_id
    left join post_links_summary pls on pls.user_id = upr.user_id
    left join badge_rollup br on br.user_id = upr.user_id
    left join top_user_tag tud on tud.user_id = upr.user_id
    left join question_answer_delta qad on qad.user_id = upr.user_id
),
duplication_heat as (
    select
        p.owneruserid as user_id,
        count(*) filter (where pl.linktypeid = 3 and pl.postid = p.id) as times_marked_duplicate,
        count(distinct case when pl.linktypeid = 3 and pl.postid = p.id then pl.relatedpostid end) as distinct_dupe_targets,
        min(case when pl.linktypeid = 3 and pl.postid = p.id then pl.creationdate end) as first_dupe_date,
        max(case when pl.linktypeid = 3 and pl.postid = p.id then pl.creationdate end) as last_dupe_date
    from posts p
    left join postlinks pl on pl.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
activity_spark as (
    select
        pe.owneruserid as user_id,
        date_trunc('month', pe.creationdate) as month_bucket,
        count(*) as posts_in_month,
        sum(pe.score) as score_in_month
    from posts_enriched pe
    where pe.owneruserid is not null
    group by pe.owneruserid, date_trunc('month', pe.creationdate)
),
activity_piv as (
    select
        a.user_id,
        sum(a.posts_in_month) filter (where a.month_bucket >= now() - interval '3 months') as posts_last_3mo,
        sum(a.score_in_month) filter (where a.month_bucket >= now() - interval '3 months') as score_last_3mo,
        sum(a.posts_in_month) filter (where a.month_bucket >= now() - interval '12 months') as posts_last_12mo,
        sum(a.score_in_month) filter (where a.month_bucket >= now() - interval '12 months') as score_last_12mo
    from activity_spark a
    group by a.user_id
),
question_close_summary as (
    select
        p.owneruserid as user_id,
        count(*) as closed_questions,
        count(*) filter (where ce.reopen_events_count > 0) as closed_then_reopened,
        avg(extract(epoch from (ce.first_close_date - p.creationdate)) / 3600.0)::numeric(18,4) as avg_hours_to_first_close
    from posts p
    join close_events ce on ce.postid = p.id
    where p.posttypeid = 1 and p.owneruserid is not null
    group by p.owneruserid
),
string_fun as (
    select
        u.id as user_id,
        upper(coalesce(nullif(u.displayname,''),'(NO NAME)')) as display_upper,
        length(coalesce(u.websiteurl,'')) as website_len,
        case
            when u.websiteurl ilike 'http%' then split_part(replace(replace(split_part(u.websiteurl,'//',2), 'www.', ''), '/', ''), '?', 1)
            else null
        end as website_domain,
        case when u.emailhash ~ '^[0-9a-f]{32}$' then u.emailhash else null end as emailhash_hex
    from users u
)
select
    ru.user_id,
    ru.displayname,
    sf.display_upper,
    ru.location_norm,
    ru.signup_month,
    ru.q_count,
    ru.a_count,
    ru.total_post_score,
    ru.avg_post_score,
    ru.median_post_score,
    ru.max_views,
    ru.first_post_date,
    ru.last_post_date,
    coalesce(rk.net_votes_received,0) as net_votes_received,
    rk.upvote_ratio,
    rk.bounties_started_on_user_posts,
    rk.bounty_total_amount,
    rk.comments_on_user_posts,
    rk.avg_comment_score_on_user_posts,
    rk.last_comment_date_on_user_posts,
    rk.linkouts,
    rk.duped_as_duplicate,
    rk.duped_original,
    rk.badges_total,
    rk.gold_badges,
    rk.silver_badges,
    rk.bronze_badges,
    rk.tag_badges,
    rk.first_badge_date,
    rk.last_badge_date,
    rk.top_tag,
    rk.top_tag_posts,
    rk.top_tag_score,
    rk.top_tag_avg_score,
    rk.q_to_a_ratio,
    rk.score_per_post,
    rk.rank_in_location,
    rk.global_rank,
    coalesce(dh.times_marked_duplicate,0) as times_marked_duplicate,
    coalesce(dh.distinct_dupe_targets,0) as distinct_dupe_targets,
    dh.first_dupe_date,
    dh.last_dupe_date,
    coalesce(ap.posts_last_3mo,0) as posts_last_3mo,
    coalesce(ap.score_last_3mo,0) as score_last_3mo,
    coalesce(ap.posts_last_12mo,0) as posts_last_12mo,
    coalesce(ap.score_last_12mo,0) as score_last_12mo,
    coalesce(qcs.closed_questions,0) as closed_questions,
    coalesce(qcs.closed_then_reopened,0) as closed_then_reopened,
    qcs.avg_hours_to_first_close,
    sf.website_len,
    sf.website_domain,
    sf.emailhash_hex
from recent_users ru
left join ranked_users rk on rk.user_id = ru.user_id
left join duplication_heat dh on dh.user_id = ru.user_id
left join activity_piv ap on ap.user_id = ru.user_id
left join question_close_summary qcs on qcs.user_id = ru.user_id
left join string_fun sf on sf.user_id = ru.user_id
where (ru.rn_loc_rep <= 100 or rk.global_rank <= 1000)
  and (
    coalesce(rk.score_per_post,0) > 0
    or coalesce(ap.posts_last_12mo,0) > 5
    or coalesce(rk.badges_total,0) >= 3
  )
order by rk.global_rank nulls last, ru.location_norm, ru.user_id
limit 1000;