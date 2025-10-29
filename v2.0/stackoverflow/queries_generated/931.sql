-- {"query": "931.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2737} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_global_newest
    from users u
),
active_posts as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.lastactivitydate,
        p.tags,
        coalesce(p.title, substring(p.body from 1 for 80)) as title_or_snippet,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.creationdate >= (select min(creationdate) from users) -- widen scan, not particularly selective
),
user_activity as (
    select
        ru.user_id,
        count(*) filter (where ap.posttypeid = 1) as q_count,
        count(*) filter (where ap.posttypeid = 2) as a_count,
        sum(ap.score) as total_post_score,
        sum(coalesce(ap.viewcount,0)) as total_views,
        sum(case when ap.is_closed = 1 then 1 else 0 end) as closed_posts
    from recent_users ru
    left join active_posts ap
        on ap.owneruserid = ru.user_id
    group by ru.user_id
),
votes_agg as (
    select
        p.owneruserid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_rcvd,
        count(*) filter (where v.votetypeid = 3) as downvotes_rcvd,
        count(*) filter (where v.votetypeid = 10) as deletions_rcvd,
        max(v.creationdate) as last_vote_time
    from posts p
    left join votes v
        on v.postid = p.id
    group by p.owneruserid
),
badges_agg as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
comment_agg as (
    select
        coalesce(c.userid, p.owneruserid) as user_id,
        count(*) as comment_count,
        sum(c.score) as comment_score_sum,
        avg(nullif(c.score,0)) as comment_score_avg_nonzero,
        max(c.creationdate) as last_comment_date
    from comments c
    left join posts p on p.id = c.postid
    group by coalesce(c.userid, p.owneruserid)
),
links_agg as (
    select
        p.owneruserid as user_id,
        count(*) filter (where pl.linktypeid = 1) as links_linked,
        count(*) filter (where pl.linktypeid = 3) as links_duplicate,
        count(distinct pl.relatedpostid) as distinct_related_targets
    from postlinks pl
    join posts p on p.id = pl.postid
    group by p.owneruserid
),
posthistory_signals as (
    select
        p.owneruserid as user_id,
        count(*) filter (where ph.posthistorytypeid in (10,35)) as closures_migrations,
        count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied,
        count(*) filter (where ph.posthistorytypeid in (50)) as community_bumps,
        max(case when ph.posthistorytypeid in (10) then try_cast(ph.comment as int) end) as any_close_reason_id_sample
    from posthistory ph
    join posts p on p.id = ph.postid
    group by p.owneruserid
),
tag_explode as (
    select
        ap.owneruserid as user_id,
        lower(trim(t)) as tagname_norm
    from active_posts ap
    cross join lateral unnest(
        case
            when ap.tags is null then array[]::varchar[]
            when length(ap.tags) <= 2 then array[]::varchar[]
            else string_to_array(substring(ap.tags, 2, length(ap.tags)-2), '><')
        end
    ) as t
),
top_tags as (
    select
        te.user_id,
        array_agg(tagname_norm order by cnt desc, tagname_norm asc)[1:3] as top3_tags,
        max(cnt) as top_tag_count
    from (
        select user_id, tagname_norm, count(*) as cnt
        from tag_explode
        group by user_id, tagname_norm
    ) s
    group by te.user_id
),
tag_meta as (
    select
        te.user_id,
        count(distinct te.tagname_norm) as distinct_tags_used,
        sum(t.count) as total_tag_global_count,
        count(*) filter (where tg.ismoderatoronly = 1) as mod_only_tags_used,
        count(*) filter (where tg.isrequired = 1) as required_tags_used
    from tag_explode te
    left join tags tg on tg.tagname = te.tagname_norm
    left join tags t on t.tagname = te.tagname_norm
    group by te.user_id
),
user_rankings as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.cohort_month,
        ua.q_count,
        ua.a_count,
        ua.total_post_score,
        ua.total_views,
        va.upvotes_rcvd,
        va.downvotes_rcvd,
        ba.badge_count,
        ba.gold_badges,
        ba.silver_badges,
        ba.bronze_badges,
        coalesce(ua.q_count,0) + coalesce(ua.a_count,0) as total_posts,
        coalesce(va.upvotes_rcvd,0) - coalesce(va.downvotes_rcvd,0) as net_votes,
        coalesce(ua.total_views,0) as views_sum,
        coalesce(cm.comment_count,0) as comments_made_or_received,
        coalesce(ph.closures_migrations,0) as close_migrate_events,
        coalesce(la.links_duplicate,0) as dup_links,
        coalesce(la.links_linked,0) as linked_links,
        coalesce(tm.distinct_tags_used,0) as distinct_tags_used,
        coalesce(tm.total_tag_global_count,0) as global_tag_weight,
        coalesce(tm.mod_only_tags_used,0) as mod_only_tags_used,
        coalesce(tm.required_tags_used,0) as required_tags_used,
        coalesce(ph.suggested_edits_applied,0) as suggested_edits_applied,
        coalesce(ph.community_bumps,0) as community_bumps,
        va.last_vote_time,
        cm.last_comment_date,
        ba.last_badge_date,
        ba.first_badge_date,
        tt.top3_tags
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join votes_agg va on va.user_id = ru.user_id
    left join badges_agg ba on ba.user_id = ru.user_id
    left join comment_agg cm on cm.user_id = ru.user_id
    left join posthistory_signals ph on ph.user_id = ru.user_id
    left join links_agg la on la.user_id = ru.user_id
    left join tag_meta tm on tm.user_id = ru.user_id
    left join top_tags tt on tt.user_id = ru.user_id
),
scored as (
    select
        ur.*,
        -- composite activity score with mixed signals and NULL handling
        (
            0.30 * ln(1 + coalesce(ur.total_posts,0)) +
            0.20 * ln(1 + greatest(coalesce(ur.total_post_score,0),0)) +
            0.15 * ln(1 + greatest(coalesce(ur.views_sum,0),0)) +
            0.20 * ln(1 + greatest(coalesce(ur.net_votes,0),0)) +
            0.10 * ln(1 + coalesce(ur.badge_count,0)) +
            0.05 * ln(1 + coalesce(ur.distinct_tags_used,0))
        ) -
        (
            0.10 * ln(1 + greatest(coalesce(ur.downvotes_rcvd,0),0)) +
            0.08 * ln(1 + coalesce(ur.close_migrate_events,0))
        ) as activity_score,
        case
            when ur.reputation >= 100000 then 'legend'
            when ur.reputation >= 20000 then 'expert'
            when ur.reputation >= 3000 then 'regular'
            when ur.reputation >= 200 then 'newbie'
            else 'fresh'
        end as rep_tier,
        dense_rank() over (partition by date_trunc('year', ur.creationdate) order by coalesce(ur.total_post_score, -999999) desc, ur.net_votes desc, ur.user_id) as yearly_score_rank,
        percentile_disc(0.9) within group (order by coalesce(ur.total_post_score,0)) over () as pct90_total_post_score
    from user_rankings ur
),
with_outliers as (
    select
        s.*,
        case when s.total_post_score > s.pct90_total_post_score then 1 else 0 end as is_score_outlier
    from scored s
),
final_rows as (
    select
        w.user_id,
        w.displayname,
        w.rep_tier,
        w.activity_score,
        w.total_posts,
        w.q_count,
        w.a_count,
        w.net_votes,
        w.views_sum,
        w.badge_count,
        w.gold_badges,
        w.silver_badges,
        w.bronze_badges,
        w.distinct_tags_used,
        w.global_tag_weight,
        w.mod_only_tags_used,
        w.required_tags_used,
        w.suggested_edits_applied,
        w.community_bumps,
        w.dup_links,
        w.linked_links,
        coalesce(array_to_string(w.top3_tags, ','), 'no-tags') as top3_tags_csv,
        w.yearly_score_rank,
        w.is_score_outlier,
        w.cohort_month,
        coalesce(w.last_vote_time, w.last_comment_date, w.last_badge_date, w.creationdate) as last_engagement_guess
    from with_outliers w
    where coalesce(w.total_posts,0) + coalesce(w.comments_made_or_received,0) > 0
)
select *
from final_rows fr
where
    -- complicated predicate mixing string, numeric, nulls, and correlated subqueries
    (
        fr.activity_score >= (
            select avg(activity_score) + stddev_pop(activity_score)
            from with_outliers
            where rep_tier in ('regular','expert','legend')
        )
        or (fr.rep_tier in ('expert','legend') and fr.net_votes > 0 and fr.is_score_outlier = 1)
    )
    and (
        fr.top3_tags_csv ilike any (array['%sql%','%python%','%java%','%javascript%'])
        or position('data' in fr.top3_tags_csv) > 0
        or fr.distinct_tags_used >= 5
    )
    and (
        fr.last_engagement_guess is not null
        and fr.last_engagement_guess >= (select min(creationdate) from posts)
    )
    and (
        exists (
            select 1
            from posts p
            where p.owneruserid = fr.user_id
              and p.posttypeid in (1,2)
              and coalesce(p.score,0) >= all (
                  select coalesce(p2.score,0)
                  from posts p2
                  where p2.owneruserid = fr.user_id
                    and p2.posttypeid in (1,2)
              )
        )
        or exists (
            select 1
            from comments c
            where c.userid = fr.user_id
              and length(c.text) > 120
        )
    )
order by
    fr.activity_score desc,
    fr.yearly_score_rank asc,
    fr.net_votes desc,
    fr.user_id
limit 250;