-- {"query": "120.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3026} 
with recent_activity as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.closeddate,
        coalesce(p.lastactivitydate, p.creationdate) as last_activity,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where coalesce(p.lastactivitydate, p.creationdate) >= now() - interval '365 days'
),
user_aug as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_created,
        u.location,
        u.upvotes,
        u.downvotes,
        u.views as profile_views,
        (u.upvotes - u.downvotes) as vote_delta,
        nullif(trim(coalesce(u.websiteurl, '')), '') as website_norm
    from users u
),
badges_rollup as (
    select
        b.userid,
        count(*) as badges_total,
        sum(case when b.class = 1 then 1 else 0 end) as gold_count,
        sum(case when b.class = 2 then 1 else 0 end) as silver_count,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
votes_rollup as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 5) as favorites,
        count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
        sum(coalesce(v.bountyamount,0)) as bounty_amount_total,
        min(v.creationdate) as first_vote_at,
        max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
comments_rollup as (
    select
        c.postid,
        count(*) as comment_count,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_comment_at,
        string_agg(distinct left(coalesce(c.userdisplayname, ''), 20), ', ' order by left(coalesce(c.userdisplayname, ''), 20)) as distinct_commenters
    from comments c
    group by c.postid
),
links_rollup as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 1) as links_linked,
        count(*) filter (where pl.linktypeid = 3) as links_duplicates,
        count(*) as links_total,
        max(pl.creationdate) as last_link_at
    from postlinks pl
    group by pl.postid
),
close_reasons as (
    select
        ph.postid,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id_raw
    from posthistory ph
    where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)
    group by ph.postid
),
question_tag_expansion as (
    select
        p.id as post_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag_name
    from posts p
    where p.posttypeid = 1 and p.tags is not null and p.tags like '<%>'
),
tag_popularity as (
    select
        qte.post_id,
        avg(t.count) as avg_tag_popularity,
        max(t.count) as max_tag_popularity,
        min(t.count) as min_tag_popularity,
        count(*) as tag_count
    from question_tag_expansion qte
    left join tags t on lower(t.tagname) = lower(qte.tag_name)
    group by qte.post_id
),
question_answer_stats as (
    select
        q.id as question_id,
        count(a.id) as answers_count,
        max(a.score) as max_answer_score,
        avg(a.score) filter (where a.score is not null) as avg_answer_score,
        max(a.creationdate) as last_answer_at,
        count(*) filter (where a.owneruserid is null) as anon_answer_count
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.id
),
user_activity_window as (
    select
        ra.owneruserid as user_id,
        ra.post_id,
        ra.creationdate as post_created,
        row_number() over (partition by ra.owneruserid order by ra.creationdate desc nulls last) as rn_recent_post,
        count(*) over (partition by ra.owneruserid) as posts_last_year
    from recent_activity ra
    where ra.owneruserid is not null
),
latest_user_post as (
    select uaw.user_id, uaw.post_id as latest_post_id, uaw.post_created as latest_post_created
    from user_activity_window uaw
    where uaw.rn_recent_post = 1
),
post_quality_score as (
    select
        ra.post_id,
        (coalesce(ra.score,0) * 2)
        + coalesce(vr.upvotes,0)
        - coalesce(vr.downvotes,0)
        + case when ra.viewcount is null then 0 else least(ra.viewcount / 100, 50) end
        + case when ra.is_closed = 1 then -20 else 0 end
        + coalesce((select count(*) from comments c2 where c2.postid = ra.post_id and c2.score > 0), 0) as quality_score
    from recent_activity ra
    left join votes_rollup vr on vr.postid = ra.post_id
),
qualified_posts as (
    select
        ra.post_id,
        ra.posttypeid,
        ra.owneruserid,
        ra.creationdate,
        ra.score,
        ra.viewcount,
        ra.title,
        ra.tags,
        ra.is_closed,
        pq.quality_score,
        rank() over (partition by ra.posttypeid order by pq.quality_score desc, ra.viewcount desc nulls last) as rnk_by_type
    from recent_activity ra
    join post_quality_score pq on pq.post_id = ra.post_id
    where
        (ra.score is not null and pq.quality_score is not null)
        and (
            ra.score > 5
            or (coalesce(ra.viewcount,0) > 1000 and pq.quality_score > 10)
            or (ra.is_closed = 0 and pq.quality_score > 30)
        )
),
user_effective as (
    select
        ua.user_id,
        ua.displayname,
        ua.reputation,
        ua.location,
        ua.vote_delta,
        br.badges_total,
        br.gold_count,
        br.silver_count,
        br.bronze_count,
        coalesce(br.last_badge_date, ua.user_created) as last_badge_or_created
    from user_aug ua
    left join badges_rollup br on br.userid = ua.user_id
),
closed_reason_lookup as (
    select
        crt.id::text as reason_id,
        crt.name as reason_name
    from closereasontypes crt
),
dup_network as (
    select
        pl.relatedpostid as canonical_id,
        count(*) as dup_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.relatedpostid
),
top_posts_union as (
    select qp.post_id, qp.posttypeid, qp.owneruserid, qp.quality_score, qp.rnk_by_type
    from qualified_posts qp
    where qp.rnk_by_type <= 100

    union all

    select ra.post_id, ra.posttypeid, ra.owneruserid, pq.quality_score, null::int as rnk_by_type
    from recent_activity ra
    join post_quality_score pq on pq.post_id = ra.post_id
    where ra.is_closed = 0 and pq.quality_score >= 75

    union

    select ra.post_id, ra.posttypeid, ra.owneruserid, pq.quality_score, null::int as rnk_by_type
    from recent_activity ra
    join post_quality_score pq on pq.post_id = ra.post_id
    where ra.is_closed = 1 and pq.quality_score >= 50
),
final as (
    select
        tp.post_id,
        pt.name as post_type,
        coalesce(p.title, concat('[Post ', tp.post_id::text, ']')) as title,
        p.creationdate as post_created,
        p.lastactivitydate as post_last_activity,
        p.viewcount,
        p.score as post_score,
        ue.user_id,
        ue.displayname as owner_name,
        ue.reputation as owner_reputation,
        ue.location as owner_location,
        ue.badges_total,
        ue.gold_count,
        ue.silver_count,
        ue.bronze_count,
        vr.upvotes,
        vr.downvotes,
        vr.favorites,
        vr.bounty_events,
        vr.bounty_amount_total,
        cr.last_closed_at,
        coalesce(crl.reason_name, case when cr.last_close_reason_id_raw ~ '^[0-9]+$' then 'UnknownReason_' || cr.last_close_reason_id_raw else null end) as last_close_reason,
        coalesce(ta.avg_tag_popularity, 0) as avg_tag_popularity,
        coalesce(ta.tag_count, 0) as tag_count,
        qas.answers_count,
        qas.max_answer_score,
        qas.avg_answer_score,
        qas.last_answer_at,
        lrp.latest_post_id as user_latest_post_id,
        lrp.latest_post_created as user_latest_post_created,
        coalesce(cm.comment_count, 0) as comment_count,
        cm.avg_comment_score,
        cm.last_comment_at,
        ln.links_total,
        ln.links_duplicates,
        dn.dup_count as duplicate_of_count,
        tp.quality_score,
        tp.rnk_by_type,
        row_number() over (order by tp.quality_score desc nulls last, p.viewcount desc nulls last, p.id) as overall_rank,
        dense_rank() over (partition by ue.user_id order by tp.quality_score desc nulls last) as user_post_rank,
        sum(coalesce(vr.upvotes,0)) over (partition by ue.user_id) as user_upvotes_on_selected_posts,
        sum(coalesce(vr.downvotes,0)) over (partition by ue.user_id) as user_downvotes_on_selected_posts,
        case
            when ue.reputation >= 100000 then 'Legend'
            when ue.reputation >= 50000 then 'Elite'
            when ue.reputation >= 10000 then 'Pro'
            when ue.reputation >= 1000 then 'Rising'
            else 'Newbie'
        end as owner_tier,
        case
            when p.tags ilike '%<sql>%' and p.tags ilike '%<performance>%' then 'SQL+Perf'
            when p.tags ilike '%<postgresql>%' then 'PostgreSQL'
            when p.tags ilike '%<mysql>%' then 'MySQL'
            when p.tags ilike '%<sql-server>%' then 'SQLServer'
            when p.tags is null then 'Untagged'
            else 'Other'
        end as tech_bucket
    from top_posts_union tp
    join posts p on p.id = tp.post_id
    left join posttypes pt on pt.id = p.posttypeid
    left join votes_rollup vr on vr.postid = p.id
    left join comments_rollup cm on cm.postid = p.id
    left join links_rollup ln on ln.postid = p.id
    left join close_reasons cr on cr.postid = p.id
    left join closed_reason_lookup crl on crl.reason_id = nullif(cr.last_close_reason_id_raw, '')
    left join tag_popularity ta on ta.post_id = p.id
    left join question_answer_stats qas on qas.question_id = p.id
    left join user_effective ue on ue.user_id = p.owneruserid
    left join latest_user_post lrp on lrp.user_id = p.owneruserid
    left join dup_network dn on dn.canonical_id = p.id
    where
        (
            -- complicated predicate with null logic and string eval
            (p.title is not null and length(trim(p.title)) > 10)
            or (p.title is null and p.body ilike any (array['%SQL%','%performance%','%join%'])
                and coalesce(p.viewcount,0) > 500)
        )
        and (
            -- exclude obvious wikis and community owned
            p.posttypeid in (1,2)
            and coalesce(p.communityowneddate, timestamp '1900-01-01') = timestamp '1900-01-01'
        )
)
select
    f.*,
    case
        when f.answers_count is null and f.post_type = 'Answer' then 'AnswerWithoutQuestionStats'
        when f.answers_count = 0 and f.post_type = 'Question' then 'Unanswered'
        when f.avg_answer_score is not null and f.avg_answer_score > 2 then 'Well-Received'
        when f.last_close_reason is not null then 'Closed'
        else 'OtherStatus'
    end as status_bucket
from final f
where
    -- correlated subquery to filter by user having at least two high-quality posts in selection
    exists (
        select 1
        from final f2
        where f2.user_id = f.user_id
          and f2.quality_score >= 40
        having count(*) filter (where f2.quality_score >= 40) >= 2
    )
order by f.overall_rank
limit 500;