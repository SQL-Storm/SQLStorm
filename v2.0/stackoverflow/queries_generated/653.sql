-- {"query": "653.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3533} 
with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
        date_trunc('month', u.creationdate) as create_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_global
    from users u
    where u.creationdate >= (select max(creationdate) - interval '730 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score, 0)) as post_score_sum,
        sum(coalesce(p.viewcount, 0)) as views_sum,
        max(p.lastactivitydate) as last_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
badge_tiers as (
    select
        b.userid as user_id,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) as total_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
post_quality as (
    select
        p.owneruserid as user_id,
        percentile_cont(0.5) within group (order by coalesce(p.score,0)) as median_post_score,
        percentile_cont(0.9) within group (order by coalesce(p.viewcount,0)) as p90_views,
        avg(case when p.posttypeid = 1 then coalesce(p.favoritecount,0) end) as avg_fav_on_questions,
        count(*) filter (where p.score >= 10) as hi_score_posts,
        count(*) filter (where p.posttypeid=1 and p.acceptedanswerid is not null) as accepted_qs,
        count(distinct case when p.posttypeid=2 then p.parentid end) as answered_questions_distinct
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
dup_network as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.linktypeid,
        p.owneruserid as post_owner_id,
        rp.owneruserid as related_owner_id
    from postlinks pl
    join posts p on p.id = pl.postid
    join posts rp on rp.id = pl.relatedpostid
    where pl.linktypeid in (1,3)
),
dup_stats as (
    select
        dn.post_owner_id as user_id,
        count(*) filter (where dn.linktypeid = 3) as duplicates_marked,
        count(*) filter (where dn.linktypeid = 1) as linked_posts,
        count(distinct dn.relatedpostid) as related_unique
    from dup_network dn
    group by dn.post_owner_id
),
close_events as (
    select
        ph.postid,
        ph.userid,
        ph.creationdate,
        try_cast(nullif(ph.comment,'') as int) as close_reason_id_raw,
        case
            when ph.posthistorytypeid = 10 then try_cast(nullif(ph.comment,'') as int)
            else null
        end as close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11,12,13,35)
),
close_reason_names as (
    select
        ce.postid,
        ce.userid as user_id,
        ce.creationdate,
        cr.name as close_reason_name
    from close_events ce
    left join closereasontypes cr on cr.id = ce.close_reason_id
),
close_stats as (
    select
        crn.user_id,
        count(*) filter (where crn.close_reason_name ilike '%duplicate%') as close_dup_votes,
        count(*) filter (where crn.close_reason_name ilike '%off-topic%') as close_offtopic_votes,
        count(*) as close_total_votes
    from close_reason_names crn
    where crn.user_id is not null
    group by crn.user_id
),
vote_agg as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_amount_total,
        max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
tag_interactions as (
    select
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag_name
    from posts p
    where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
),
top_tags as (
    select
        ti.user_id,
        t.tagname,
        count(*) as tag_uses,
        row_number() over (partition by ti.user_id order by count(*) desc, t.tagname) as rn
    from tag_interactions ti
    join tags t on lower(t.tagname) = lower(ti.tag_name)
    group by ti.user_id, t.tagname
),
user_rank as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        coalesce(ua.q_count,0) as q_count,
        coalesce(ua.a_count,0) as a_count,
        coalesce(ua.post_score_sum,0) as post_score_sum,
        coalesce(ua.views_sum,0) as views_sum,
        coalesce(cs.comment_count,0) as comment_count,
        coalesce(bt.total_badges,0) as total_badges,
        coalesce(bt.gold_badges,0) as gold_badges,
        coalesce(bt.silver_badges,0) as silver_badges,
        coalesce(bt.bronze_badges,0) as bronze_badges,
        coalesce(pq.median_post_score,0) as median_post_score,
        coalesce(pq.p90_views,0) as p90_views,
        coalesce(pq.avg_fav_on_questions,0) as avg_fav_on_questions,
        coalesce(pq.hi_score_posts,0) as hi_score_posts,
        coalesce(pq.accepted_qs,0) as accepted_qs,
        coalesce(pq.answered_questions_distinct,0) as answered_questions_distinct,
        coalesce(ds.duplicates_marked,0) as duplicates_marked,
        coalesce(ds.linked_posts,0) as linked_posts,
        coalesce(ds.related_unique,0) as related_unique,
        coalesce(cz.close_dup_votes,0) as close_dup_votes,
        coalesce(cz.close_offtopic_votes,0) as close_offtopic_votes,
        coalesce(cz.close_total_votes,0) as close_total_votes,
        coalesce(va.upvotes_cast,0) as upvotes_cast,
        coalesce(va.downvotes_cast,0) as downvotes_cast,
        coalesce(va.bounties_started,0) as bounties_started,
        coalesce(va.bounty_amount_total,0) as bounty_amount_total,
        greatest(
            coalesce(ua.last_activity, timestamp 'epoch'),
            coalesce(cs.last_comment_date, timestamp 'epoch'),
            coalesce(va.last_vote_date, timestamp 'epoch')
        ) as last_seen_activity
    from recent_users u
    left join user_activity ua on ua.user_id = u.id
    left join comment_stats cs on cs.user_id = u.id
    left join badge_tiers bt on bt.user_id = u.id
    left join post_quality pq on pq.user_id = u.id
    left join dup_stats ds on ds.user_id = u.id
    left join close_stats cz on cz.user_id = u.id
    left join vote_agg va on va.user_id = u.id
),
scored as (
    select
        ur.*,
        -- composite engagement/quality score with mix of logs and ratios
        (
            0.40 * ln(1 + ur.post_score_sum + ur.views_sum/50.0)
          + 0.20 * ln(1 + ur.q_count + ur.a_count*1.5)
          + 0.15 * ln(1 + ur.total_badges*2 + ur.gold_badges*5 + ur.silver_badges*3 + ur.bronze_badges)
          + 0.10 * (case when ur.a_count > 0 then least(1.0, ur.hi_score_posts::numeric / nullif(ur.a_count,0)) else 0 end)
          + 0.05 * (case when ur.q_count > 0 then least(1.0, ur.accepted_qs::numeric / nullif(ur.q_count,0)) else 0 end)
          + 0.05 * ln(1 + ur.upvotes_cast - ur.downvotes_cast + abs(ur.downvotes_cast))
          + 0.05 * ln(1 + ur.bounty_amount_total)
        ) as composite_score,
        row_number() over (
            order by
                (
                    0.40 * ln(1 + ur.post_score_sum + ur.views_sum/50.0)
                  + 0.20 * ln(1 + ur.q_count + ur.a_count*1.5)
                  + 0.15 * ln(1 + ur.total_badges*2 + ur.gold_badges*5 + ur.silver_badges*3 + ur.bronze_badges)
                  + 0.10 * (case when ur.a_count > 0 then least(1.0, ur.hi_score_posts::numeric / nullif(ur.a_count,0)) else 0 end)
                  + 0.05 * (case when ur.q_count > 0 then least(1.0, ur.accepted_qs::numeric / nullif(ur.q_count,0)) else 0 end)
                  + 0.05 * ln(1 + ur.upvotes_cast - ur.downvotes_cast + abs(ur.downvotes_cast))
                  + 0.05 * ln(1 + ur.bounty_amount_total)
                ) desc,
                ur.reputation desc,
                ur.user_id desc
        ) as rank_overall
    from user_rank ur
),
top_per_user_tags as (
    select
        tt.user_id,
        string_agg(tt.tagname || ':' || tt.tag_uses, ', ' order by tt.tag_uses desc, tt.tagname) filter (where tt.rn <= 5) as top5_tags
    from (
        select user_id, tagname, tag_uses, rn
        from top_tags
        where rn <= 5
    ) tt
    group by tt.user_id
),
active_intervals as (
    select
        ur.user_id,
        date_trunc('month', generate_series(date_trunc('month', now() - interval '12 months'), date_trunc('month', now()), interval '1 month')) as month_bucket
    from (select distinct user_id from scored) ur
),
monthly_posts as (
    select
        p.owneruserid as user_id,
        date_trunc('month', p.creationdate) as month_bucket,
        count(*) filter (where p.posttypeid=1) as q_cnt,
        count(*) filter (where p.posttypeid=2) as a_cnt
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= now() - interval '13 months'
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
recent_cadence as (
    select
        ai.user_id,
        avg(coalesce(mp.q_cnt,0) + coalesce(mp.a_cnt,0)) as avg_monthly_posts_last_year,
        sum(coalesce(mp.q_cnt,0) + coalesce(mp.a_cnt,0)) filter (where ai.month_bucket >= date_trunc('month', now() - interval '3 months')) as last_quarter_posts
    from active_intervals ai
    left join monthly_posts mp on mp.user_id = ai.user_id and mp.month_bucket = ai.month_bucket
    group by ai.user_id
),
name_parts as (
    select
        u.id as user_id,
        split_part(coalesce(nullif(u.displayname,''),'Unknown'), ' ', 1) as first_token,
        regexp_replace(coalesce(u.location,''), '\s+', ' ', 'g') as location_norm
    from users u
)
select
    s.rank_overall,
    s.user_id,
    s.displayname,
    np.first_token as displayname_first_token,
    s.reputation,
    s.q_count,
    s.a_count,
    s.post_score_sum,
    s.views_sum,
    s.comment_count,
    s.total_badges,
    s.gold_badges,
    s.silver_badges,
    s.bronze_badges,
    round(coalesce(s.median_post_score,0)::numeric,2) as median_post_score,
    round(coalesce(s.p90_views,0)::numeric,2) as p90_views,
    round(coalesce(s.avg_fav_on_questions,0)::numeric,3) as avg_fav_on_questions,
    s.hi_score_posts,
    s.accepted_qs,
    s.answered_questions_distinct,
    s.duplicates_marked,
    s.linked_posts,
    s.related_unique,
    s.close_dup_votes,
    s.close_offtopic_votes,
    s.close_total_votes,
    s.upvotes_cast,
    s.downvotes_cast,
    s.bounties_started,
    s.bounty_amount_total,
    s.last_seen_activity,
    round(s.composite_score::numeric, 4) as composite_score,
    coalesce(tt.top5_tags, '(none)') as top5_tags,
    case
        when s.reputation >= 100000 then 'Legend'
        when s.reputation >= 50000 then 'Elite'
        when s.reputation >= 10000 then 'Pro'
        when s.reputation >= 2000 then 'Experienced'
        when s.reputation >= 200 then 'Contributor'
        else 'Newbie'
    end as rep_bucket,
    case
        when s.downvotes_cast > s.upvotes_cast then 'Net-negative voter'
        when s.downvotes_cast > 0 and s.upvotes_cast = 0 then 'Only-downvoter'
        when s.upvotes_cast > 0 and s.downvotes_cast = 0 then 'Only-upvoter'
        when s.upvotes_cast = 0 and s.downvotes_cast = 0 then 'No votes cast'
        else 'Mixed voter'
    end as voting_profile,
    rc.avg_monthly_posts_last_year,
    coalesce(rc.last_quarter_posts,0) as last_quarter_posts,
    case when s.last_seen_activity >= now() - interval '30 days' then true else false end as active_last_30d,
    np.location_norm
from scored s
left join top_per_user_tags tt on tt.user_id = s.user_id
left join recent_cadence rc on rc.user_id = s.user_id
left join name_parts np on np.user_id = s.user_id
where (
    s.reputation >= 1000
    or s.composite_score >= (
        select percentile_cont(0.75) within group (order by composite_score) from scored
    )
)
and coalesce(s.displayname,'') not ilike any (array['%bot%','%ci%','%test%'])
order by s.rank_overall
limit 200;