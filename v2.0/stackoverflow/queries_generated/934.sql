-- {"query": "934.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3387} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
),
top_recent_users as (
    select *
    from recent_users
    where rn <= 500
),
user_posts as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.closeddate,
        p.communityowneddate
    from posts p
    where p.owneruserid is not null
),
post_quality as (
    select
        up.post_id,
        up.user_id,
        up.posttypeid,
        up.creationdate,
        up.score,
        up.viewcount,
        up.title,
        up.tags,
        up.answercount,
        up.commentcount,
        up.favoritecount,
        up.closeddate,
        up.communityowneddate,
        -- composite quality metric with guard against div-by-zero and NULLs
        (coalesce(up.score, 0) * 2.0
         + coalesce(up.viewcount, 0) / nullif(greatest(1, extract(epoch from age(now(), up.creationdate)) / 86400)::numeric, 0)
         + coalesce(up.answercount, 0) * 5.0
         + coalesce(up.commentcount, 0) * 0.5
        ) as quality_score
    from user_posts up
),
posts_with_tags as (
    -- explode tags into rows; tags are like '<sql><performance>'
    select
        pq.post_id,
        pq.user_id,
        lower(trim(tg)) as tag_name,
        pq.posttypeid,
        pq.creationdate,
        pq.score,
        pq.viewcount,
        pq.title,
        pq.quality_score
    from post_quality pq
    left join lateral (
        select unnest(
            case
                when pq.tags is null or length(pq.tags) < 3 then array[]::varchar[]
                else string_to_array(substring(pq.tags, 2, length(pq.tags) - 2), '><')
            end
        ) as tg
    ) x on true
),
vote_summaries as (
    select
        v.postid as post_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        max(case when v.votetypeid in (8,9) then coalesce(v.bountyamount, 0) else 0 end) as max_bounty
    from votes v
    group by v.postid
),
comment_activity as (
    select
        c.postid as post_id,
        count(*) as comment_count,
        max(c.creationdate) as last_comment_at,
        max(length(coalesce(c.text, ''))) filter (where c.text is not null) as max_comment_len
    from comments c
    group by c.postid
),
closure_info as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 11) as first_reopened_at,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        -- parse close reason id from comment field when available (numeric at start)
        max(
            nullif(regexp_replace(coalesce(ph.comment, ''), '[^0-9]', '', 'g'), '')
        ) as last_close_reason_id_text
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
dup_links as (
    select
        pl.postid as post_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as related_links
    from postlinks pl
    group by pl.postid
),
badge_summaries as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
post_type_names as (
    select id, name from posttypes
),
user_activity as (
    select
        pwt.user_id,
        count(*) as total_posts,
        count(*) filter (where pwt.posttypeid = 1) as question_count,
        count(*) filter (where pwt.posttypeid = 2) as answer_count,
        avg(pwt.quality_score) as avg_quality,
        sum(case when pwt.score > 0 then 1 else 0 end)::numeric / nullif(count(*),0) as pos_score_ratio,
        max(pwt.creationdate) as last_post_at
    from posts_with_tags pwt
    group by pwt.user_id
),
ranked_posts as (
    select
        pwt.*,
        coalesce(vs.upvotes, 0) as upvotes,
        coalesce(vs.downvotes, 0) as downvotes,
        coalesce(vs.favorites, 0) as favorites,
        coalesce(vs.max_bounty, 0) as max_bounty,
        coalesce(ca.comment_count, 0) as comment_count,
        ca.last_comment_at,
        coalesce(dl.duplicate_links, 0) as duplicate_links,
        coalesce(dl.related_links, 0) as related_links,
        ci.first_closed_at,
        ci.first_reopened_at,
        ci.close_events,
        ci.reopen_events,
        nullif(ci.last_close_reason_id_text, '')::int as last_close_reason_id,
        dense_rank() over (
            partition by pwt.user_id
            order by (pwt.quality_score
                     + coalesce(vs.upvotes,0) * 1.5
                     - coalesce(vs.downvotes,0) * 1.0
                     + coalesce(vs.favorites,0) * 0.5
                     + coalesce(vs.max_bounty,0) * 0.1
                     + coalesce(ca.comment_count,0) * 0.2
                     - coalesce(dl.duplicate_links,0) * 2.0
            ) desc,
            pwt.creationdate desc,
            pwt.post_id desc
        ) as post_rank
    from posts_with_tags pwt
    left join vote_summaries vs on vs.post_id = pwt.post_id
    left join comment_activity ca on ca.post_id = pwt.post_id
    left join dup_links dl on dl.post_id = pwt.post_id
    left join closure_info ci on ci.postid = pwt.post_id
),
user_top_posts as (
    select *
    from ranked_posts
    where post_rank <= 3
),
tag_density as (
    select
        tag_name,
        count(*) as tag_use_count,
        count(distinct user_id) as distinct_users,
        percentile_cont(0.5) within group (order by score) as median_score
    from posts_with_tags
    where tag_name is not null
    group by tag_name
),
rare_tags as (
    select td.tag_name
    from tag_density td
    where td.tag_use_count between 2 and 20
),
post_enriched as (
    select
        utp.user_id,
        utp.post_id,
        utp.posttypeid,
        ptn.name as post_type_name,
        utp.creationdate as post_created_at,
        utp.score,
        utp.viewcount,
        utp.title,
        utp.tag_name,
        utp.quality_score,
        utp.upvotes,
        utp.downvotes,
        utp.favorites,
        utp.max_bounty,
        utp.comment_count,
        utp.last_comment_at,
        utp.duplicate_links,
        utp.related_links,
        utp.first_closed_at,
        utp.first_reopened_at,
        utp.close_events,
        utp.reopen_events,
        utp.last_close_reason_id,
        case when rt.tag_name is not null then 1 else 0 end as is_rare_tag
    from user_top_posts utp
    left join post_type_names ptn on ptn.id = utp.posttypeid
    left join rare_tags rt on rt.tag_name = utp.tag_name
),
user_rollup as (
    select
        tru.user_id,
        tru.displayname,
        tru.reputation,
        tru.creationdate as user_created_at,
        tru.location,
        tru.websiteurl,
        ua.total_posts,
        ua.question_count,
        ua.answer_count,
        ua.avg_quality,
        ua.pos_score_ratio,
        ua.last_post_at,
        coalesce(bs.total_badges, 0) as total_badges,
        coalesce(bs.gold_badges, 0) as gold_badges,
        coalesce(bs.silver_badges, 0) as silver_badges,
        coalesce(bs.bronze_badges, 0) as bronze_badges,
        bs.last_badge_at
    from top_recent_users tru
    left join user_activity ua on ua.user_id = tru.user_id
    left join badge_summaries bs on bs.user_id = tru.user_id
),
stringified as (
    select
        pe.user_id,
        string_agg(
            coalesce(
                '['
                || coalesce(pe.post_type_name, 'Unknown')
                || '] '
                || coalesce(nullif(btrim(pe.title), ''), '(no title)')
                || ' | score=' || coalesce(pe.score, 0)
                || ', views=' || coalesce(pe.viewcount, 0)
                || ', tag=' || coalesce(pe.tag_name, '(none)')
                || ', rare=' || case when pe.is_rare_tag=1 then 'Y' else 'N' end
                || ', votes(+/-/fav)=(' || coalesce(pe.upvotes,0) || '/' || coalesce(pe.downvotes,0) || '/' || coalesce(pe.favorites,0) || ')'
                || ', bounty=' || coalesce(pe.max_bounty,0)
                || ', comments=' || coalesce(pe.comment_count,0)
                || ', links(dup/rel)=(' || coalesce(pe.duplicate_links,0) || '/' || coalesce(pe.related_links,0) || ')'
                || ', closed=' || coalesce(to_char(pe.first_closed_at, 'YYYY-MM-DD'), 'no')
                || ', reopened=' || coalesce(to_char(pe.first_reopened_at, 'YYYY-MM-DD'), 'no')
                || ', close_reason_id=' || coalesce(pe.last_close_reason_id, 0)
                || ', qscore=' || round(coalesce(pe.quality_score,0)::numeric, 2)
                , '(n/a)'
            ),
            ' || ',
            order by pe.quality_score desc, pe.post_created_at desc, pe.post_id desc
        ) as top_posts_summary
    from post_enriched pe
    group by pe.user_id
),
bench as (
    select
        ur.user_id,
        ur.displayname,
        ur.reputation,
        ur.user_created_at,
        ur.location,
        ur.websiteurl,
        coalesce(ur.total_posts, 0) as total_posts,
        coalesce(ur.question_count, 0) as question_count,
        coalesce(ur.answer_count, 0) as answer_count,
        round(coalesce(ur.avg_quality, 0)::numeric, 3) as avg_quality,
        round(coalesce(ur.pos_score_ratio, 0)::numeric, 3) as pos_score_ratio,
        ur.last_post_at,
        ur.total_badges,
        ur.gold_badges,
        ur.silver_badges,
        ur.bronze_badges,
        ur.last_badge_at,
        coalesce(s.top_posts_summary, '(no posts)') as top_posts_summary,
        -- compute composite user benchmark score
        (
            coalesce(ur.reputation, 0) * 0.001
            + coalesce(ur.total_posts, 0) * 0.05
            + coalesce(ur.question_count, 0) * 0.03
            + coalesce(ur.answer_count, 0) * 0.07
            + coalesce(ur.avg_quality, 0) * 0.5
            + greatest(0, coalesce(ur.pos_score_ratio, 0)) * 2.0
            + coalesce(ur.gold_badges, 0) * 0.5
            + coalesce(ur.silver_badges, 0) * 0.2
            + coalesce(ur.bronze_badges, 0) * 0.1
            + case when ur.last_post_at >= now() - interval '180 days' then 1.0 else 0.0 end
        ) as benchmark_score
    from user_rollup ur
    left join stringified s on s.user_id = ur.user_id
),
dedup as (
    -- simulate set operations and null logic with union all and anti-join to remove duplicate user_ids from overlapping cohorts
    select * from bench where total_posts > 0
    union all
    select * from bench where total_posts = 0 and reputation > 0
),
final as (
    select d.*
    from dedup d
    left join (
        select user_id, count(*) as cnt
        from dedup
        group by user_id
        having count(*) > 1
    ) dup on dup.user_id = d.user_id
    where dup.user_id is null
)
select
    f.user_id,
    f.displayname,
    f.reputation,
    f.user_created_at,
    f.location,
    f.websiteurl,
    f.total_posts,
    f.question_count,
    f.answer_count,
    f.avg_quality,
    f.pos_score_ratio,
    f.last_post_at,
    f.total_badges,
    f.gold_badges,
    f.silver_badges,
    f.bronze_badges,
    f.last_badge_at,
    f.top_posts_summary,
    f.benchmark_score,
    rank() over (order by f.benchmark_score desc, f.reputation desc, f.user_created_at asc, f.user_id asc) as overall_rank
from final f
where
    -- complicated predicate mixing null logic and expressions
    (
        coalesce(f.avg_quality, 0) > 0
        or (f.total_posts = 0 and f.reputation > 100)
        or (f.gold_badges > 0 and f.pos_score_ratio is not null)
    )
    and (f.location is null or length(trim(f.location)) = 0 or position('remote' in lower(f.location)) > 0 or position(',' in f.location) > 0)
    and (f.websiteurl is null or f.websiteurl not like '%example.com%')
order by overall_rank
limit 200;