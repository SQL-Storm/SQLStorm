-- {"query": "669.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3640} 
with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.ownerduserid,
        p.title,
        p.tags,
        coalesce(nullif(trim(p.ownerdisplayname), ''), u.displayname, '[unknown]') as owner_name,
        date_trunc('month', p.creationdate) as month_bucket
    from posts p
    left join users u on u.id = p.owneruserid
    where p.creationdate >= now() - interval '3 years'
),
tag_expanded as (
    select
        rp.id as post_id,
        rp.posttypeid,
        rp.creationdate,
        rp.score,
        rp.viewcount,
        rp.owner_name,
        rp.month_bucket,
        lower(trim(t)) as tag
    from recent_posts rp
    left join lateral (
        select unnest(string_to_array(substring(rp.tags from 2 for greatest(length(rp.tags)-2,0)), '><')) as t
    ) s on true
),
user_activity as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        date_trunc('month', u.creationdate) as user_cohort,
        count(distinct p.id) filter (where p.owneruserid = u.id) as total_authored_posts,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as questions_authored,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as answers_authored,
        coalesce(sum(v.vote_type_up),0) as upvotes_given,
        coalesce(sum(v.vote_type_down),0) as downvotes_given
    from users u
    left join posts p on p.owneruserid = u.id
    left join lateral (
        select
            v2.userid,
            case when v2.votetypeid = 2 then 1 else 0 end as vote_type_up,
            case when v2.votetypeid = 3 then 1 else 0 end as vote_type_down
        from votes v2
        where v2.userid = u.id
    ) v on true
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location
),
post_interactions as (
    select
        p.id as post_id,
        count(*) filter (where vt.votetypeid = 2) as upvotes,
        count(*) filter (where vt.votetypeid = 3) as downvotes,
        count(*) filter (where vt.votetypeid = 5) as favorites,
        sum(vt.bountyamount) filter (where vt.votetypeid in (8,9)) as bounty_total,
        count(distinct c.id) as comments_count
    from posts p
    left join votes vt on vt.postid = p.id
    left join comments c on c.postid = p.id
    group by p.id
),
duplicates as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        min(pl.creationdate) as first_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
edits_cte as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_date,
        count(*) filter (where ph.posthistorytypeid = 24) as suggested_edits_applied,
        count(*) filter (where ph.posthistorytypeid in (10,11)) as open_close_flaps
    from posthistory ph
    group by ph.postid
),
tag_stats as (
    select
        te.tag,
        te.month_bucket,
        count(distinct te.post_id) as posts_with_tag,
        sum(pi.upvotes - pi.downvotes) as net_votes_with_tag,
        avg(nullif(pi.upvotes + pi.downvotes,0)) as avg_votes_activity,
        percentile_cont(0.5) within group (order by pi.upvotes - pi.downvotes) as median_net_votes
    from tag_expanded te
    left join post_interactions pi on pi.post_id = te.post_id
    group by te.tag, te.month_bucket
),
question_answer_pairs as (
    select
        q.id as question_id,
        q.title as question_title,
        q.owneruserid as question_owner_id,
        q.creationdate as question_date,
        q.score as question_score,
        q.viewcount as question_views,
        q.acceptedanswerid,
        count(a.id) as answers_count,
        sum(a.score) as answers_score_sum,
        max(a.score) as max_answer_score,
        avg(a.score) as avg_answer_score
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.id, q.title, q.owneruserid, q.creationdate, q.score, q.viewcount, q.acceptedanswerid
),
answerer_quality as (
    select
        a.owneruserid as user_id,
        count(*) as answers_posted,
        sum(case when q.acceptedanswerid = a.id then 1 else 0 end) as answers_accepted,
        avg(a.score) as avg_answer_score,
        percentile_disc(0.9) within group (order by a.score) as p90_answer_score
    from posts a
    join posts q on q.id = a.parentid and q.posttypeid = 1
    where a.posttypeid = 2
    group by a.owneruserid
),
hot_questions as (
    select
        qap.question_id,
        qap.question_title,
        qap.question_owner_id,
        qap.question_date,
        qap.question_score,
        qap.question_views,
        (qap.answers_count > 0)::int as has_answers,
        case
            when qap.question_views >= 10000 then 'very_hot'
            when qap.question_views >= 2000 then 'hot'
            when qap.question_views >= 500 then 'warm'
            else 'cold'
        end as heat_bucket
    from question_answer_pairs qap
    where coalesce(qap.question_views,0) >= 0
),
user_rollup as (
    select
        ua.user_id,
        coalesce(ua.displayname, '[anonymous]') as displayname,
        ua.reputation,
        ua.location,
        ua.user_cohort,
        ua.total_authored_posts,
        ua.questions_authored,
        ua.answers_authored,
        ua.upvotes_given,
        ua.downvotes_given,
        coalesce(aq.answers_posted,0) as answers_posted,
        coalesce(aq.answers_accepted,0) as answers_accepted,
        coalesce(aq.avg_answer_score,0) as avg_answer_score,
        coalesce(aq.p90_answer_score,0) as p90_answer_score
    from user_activity ua
    left join answerer_quality aq on aq.user_id = ua.user_id
),
post_features as (
    select
        rp.id as post_id,
        rp.posttypeid,
        rp.creationdate,
        rp.score,
        rp.viewcount,
        rp.owner_name,
        rp.month_bucket,
        pi.upvotes,
        pi.downvotes,
        pi.favorites,
        pi.bounty_total,
        pi.comments_count,
        ed.edit_count,
        ed.last_edit_date,
        ed.suggested_edits_applied,
        ed.open_close_flaps,
        d.original_post_id,
        case when d.original_post_id is not null then 1 else 0 end as is_duplicate
    from recent_posts rp
    left join post_interactions pi on pi.post_id = rp.id
    left join edits_cte ed on ed.postid = rp.id
    left join duplicates d on d.dup_post_id = rp.id
),
ranked_posts as (
    select
        pf.*,
        row_number() over (partition by pf.posttypeid order by coalesce(pf.viewcount,0) desc, coalesce(pf.score,0) desc) as rn_views,
        dense_rank() over (order by coalesce(pf.upvotes,0) - coalesce(pf.downvotes,0) desc) as dr_netvotes,
        sum(coalesce(pf.viewcount,0)) over (partition by pf.owner_name order by pf.creationdate rows between unbounded preceding and current row) as owner_cum_views
    from post_features pf
),
flagged_titles as (
    select
        p.id as post_id,
        case
            when p.title is null then 1
            when length(trim(p.title)) = 0 then 1
            when p.title ~* '(?<!\w)(help|urgent|asap|problem)(?!\w)' then 1
            else 0
        end as bad_title_flag
    from posts p
    where p.posttypeid = 1
),
post_quality_scoring as (
    select
        rp.post_id,
        rp.posttypeid,
        rp.owner_name,
        rp.creationdate,
        rp.month_bucket,
        coalesce(rp.score,0) as raw_score,
        coalesce(rp.viewcount,0) as raw_views,
        coalesce(rp.upvotes,0) - coalesce(rp.downvotes,0) as net_votes,
        coalesce(rp.favorites,0) as favorites,
        coalesce(rp.bounty_total,0) as bounty,
        coalesce(rp.comments_count,0) as comments,
        coalesce(rp.edit_count,0) as edits,
        rp.is_duplicate,
        case when ft.bad_title_flag = 1 then -5 else 0 end as title_penalty,
        case when rp.is_duplicate = 1 then -10 else 0 end as duplicate_penalty,
        -- compute a composite quality score with mixed weights
        (
            0.40 * ln(1 + greatest(coalesce(rp.viewcount,0),0)) +
            0.30 * (coalesce(rp.upvotes,0) - coalesce(rp.downvotes,0)) +
            0.10 * coalesce(rp.favorites,0) +
            0.05 * ln(1 + greatest(coalesce(rp.comments_count,0),0)) +
            0.10 * least(coalesce(rp.bounty_total,0), 500) / 50.0 +
            0.05 * least(5, greatest(0, 5 - coalesce(rp.edit_count,0))) +
            case when rp.posttypeid = 2 then 0.15 else 0 end +
            case when rp.posttypeid = 1 then 0.05 else 0 end
        ) +
        (case when ft.bad_title_flag = 1 then -5 else 0 end) +
        (case when rp.is_duplicate = 1 then -10 else 0 end) as quality_score
    from ranked_posts rp
    left join flagged_titles ft on ft.post_id = rp.post_id
),
monthly_aggregation as (
    select
        pq.month_bucket,
        pq.posttypeid,
        count(*) as posts_count,
        avg(pq.quality_score) as avg_quality_score,
        sum(case when pq.quality_score >= 10 then 1 else 0 end) as high_quality_posts,
        sum(case when pq.is_duplicate = 1 then 1 else 0 end) as duplicate_posts,
        sum(case when pq.quality_score < 0 then 1 else 0 end) as low_quality_posts
    from post_quality_scoring pq
    group by pq.month_bucket, pq.posttypeid
),
leaderboard as (
    select
        pr.owner_name,
        count(*) as posts_count,
        avg(coalesce(pr.score,0)) as avg_score,
        sum(coalesce(pr.viewcount,0)) as total_views,
        avg(coalesce(pr.upvotes,0) - coalesce(pr.downvotes,0)) as avg_net_votes,
        max(pr.owner_cum_views) as cum_views_last_post,
        min(pr.creationdate) as first_post_date,
        max(pr.creationdate) as last_post_date,
        rank() over (order by sum(coalesce(pr.viewcount,0)) desc) as r_views
    from ranked_posts pr
    group by pr.owner_name
),
final_set as (
    select
        'posts' as entity,
        pq.post_id::text as id,
        pq.owner_name,
        to_char(pq.creationdate, 'YYYY-MM-DD"T"HH24:MI:SS') as created_at,
        pq.posttypeid::text as subtype,
        round(pq.quality_score::numeric, 2)::text as metric,
        case when pq.quality_score >= 10 then 'high'
             when pq.quality_score >= 3 then 'medium'
             when pq.quality_score >= 0 then 'low'
             else 'bad' end as category
    from post_quality_scoring pq
    where pq.creationdate >= now() - interval '2 years'

    union all

    select
        'months' as entity,
        to_char(ma.month_bucket, 'YYYY-MM') as id,
        'ALL' as owner_name,
        to_char(ma.month_bucket, 'YYYY-MM-01') as created_at,
        ma.posttypeid::text as subtype,
        round(ma.avg_quality_score::numeric, 3)::text as metric,
        case
            when ma.avg_quality_score >= 8 then 'excellent'
            when ma.avg_quality_score >= 4 then 'good'
            when ma.avg_quality_score >= 1 then 'ok'
            else 'poor'
        end as category
    from monthly_aggregation ma

    union all

    select
        'leaders' as entity,
        l.owner_name as id,
        l.owner_name,
        to_char(l.last_post_date, 'YYYY-MM-DD') as created_at,
        'all' as subtype,
        l.total_views::text as metric,
        case when l.r_views <= 10 then 'top10'
             when l.r_views <= 100 then 'top100'
             else 'other' end as category
    from leaderboard l
),
tag_trends as (
    select
        ts.tag,
        ts.month_bucket,
        ts.posts_with_tag,
        ts.net_votes_with_tag,
        ts.avg_votes_activity,
        ts.median_net_votes,
        lag(ts.posts_with_tag) over (partition by ts.tag order by ts.month_bucket) as prev_posts_with_tag,
        lag(ts.net_votes_with_tag) over (partition by ts.tag order by ts.month_bucket) as prev_net_votes_with_tag
    from tag_stats ts
),
tag_trend_flags as (
    select
        tt.tag,
        tt.month_bucket,
        tt.posts_with_tag,
        tt.net_votes_with_tag,
        case
            when tt.prev_posts_with_tag is null then 'new'
            when tt.posts_with_tag >= tt.prev_posts_with_tag * 1.5 and tt.posts_with_tag >= 10 then 'surging'
            when tt.posts_with_tag <= tt.prev_posts_with_tag * 0.67 and tt.prev_posts_with_tag >= 10 then 'cooling'
            else 'steady'
        end as volume_trend,
        case
            when tt.prev_net_votes_with_tag is null then 'unknown'
            when tt.net_votes_with_tag > tt.prev_net_votes_with_tag then 'improving'
            when tt.net_votes_with_tag < tt.prev_net_votes_with_tag then 'worsening'
            else 'flat'
        end as sentiment_trend
    from tag_trends tt
),
top_tags as (
    select
        tag,
        sum(posts_with_tag) as posts_last_2y
    from tag_stats
    where month_bucket >= date_trunc('month', now() - interval '2 years')
    group by tag
    having sum(posts_with_tag) >= 50
),
final_output as (
    select
        fs.entity,
        fs.id,
        fs.owner_name,
        fs.created_at,
        fs.subtype,
        fs.metric,
        fs.category
    from final_set fs
    where fs.entity <> 'leaders' or fs.category in ('top10','top100')

    union all

    select
        'tag_trend' as entity,
        concat(ttf.tag, ':', to_char(ttf.month_bucket, 'YYYY-MM')) as id,
        ttf.tag as owner_name,
        to_char(ttf.month_bucket, 'YYYY-MM-01') as created_at,
        ttf.volume_trend as subtype,
        coalesce(ttf.net_votes_with_tag,0)::text as metric,
        ttf.sentiment_trend as category
    from tag_trend_flags ttf
    join top_tags tt on tt.tag = ttf.tag
)
select *
from final_output
order by entity, created_at, id
limit 2000;