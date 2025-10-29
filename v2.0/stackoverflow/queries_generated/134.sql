-- {"query": "134.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3201} 
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
        coalesce(p.answercount, 0) as answercount,
        p.closeddate,
        p.lastactivitydate,
        u.reputation,
        u.location,
        u.displayname as owner_name
    from posts p
    left join users u on u.id = p.owneruserid
    where p.creationdate >= now() - interval '365 days'
),
post_scores as (
    select
        ra.post_id,
        ra.posttypeid,
        ra.owneruserid,
        ra.creationdate,
        ra.title,
        ra.tags,
        ra.viewcount,
        ra.answercount,
        ra.closeddate,
        ra.lastactivitydate,
        ra.reputation,
        ra.location,
        ra.owner_name,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_sum,
        count(*) filter (where v.votetypeid in (2,3,5,8,9)) as total_vote_events
    from recent_activity ra
    left join votes v on v.postid = ra.post_id
      and v.creationdate >= ra.creationdate
    group by
        ra.post_id, ra.posttypeid, ra.owneruserid, ra.creationdate, ra.title, ra.tags,
        ra.viewcount, ra.answercount, ra.closeddate, ra.lastactivitydate, ra.reputation, ra.location, ra.owner_name
),
comment_stats as (
    select
        c.postid,
        count(*) as comment_count,
        coalesce(sum(case when c.score > 0 then 1 else 0 end),0) as positive_comments,
        max(c.creationdate) as last_comment_at,
        avg(nullif(length(c.text),0)) as avg_comment_len
    from comments c
    where c.creationdate >= now() - interval '365 days'
    group by c.postid
),
edit_events as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_count,
        max(ph.creationdate) as last_edit_at,
        bool_or(ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as had_moderation
    from posthistory ph
    where ph.creationdate >= now() - interval '365 days'
    group by ph.postid
),
linking as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        count(*) filter (where pl.linktypeid = 3) as duplicate_count,
        max(pl.creationdate) as last_link_at
    from postlinks pl
    where pl.creationdate >= now() - interval '365 days'
    group by pl.postid
),
tag_explode as (
    select
        p.id as post_id,
        unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
      and p.creationdate >= now() - interval '365 days'
),
tag_quality as (
    select
        te.post_id,
        count(*) as tag_count,
        sum(case when t.count > 0 then 1 else 0 end) as known_tags,
        avg(log(greatest(t.count,1))) as avg_tag_popularity
    from tag_explode te
    left join tags t on lower(t.tagname) = lower(te.tagname)
    group by te.post_id
),
user_badges as (
    select
        u.id as user_id,
        count(*) as total_badges,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_at
    from users u
    left join badges b on b.userid = u.id
    group by u.id
),
dup_clusters as (
    select
        q.id as original_qid,
        a.id as answer_id,
        row_number() over (partition by q.id order by a.score desc nulls last, a.creationdate asc) as rn
    from posts q
    join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
      and q.creationdate >= now() - interval '365 days'
),
accepted_vs_top as (
    select
        q.id as question_id,
        q.acceptedanswerid,
        sum(case when dc.rn = 1 then 1 else 0 end) as has_top_answer,
        sum(case when dc.rn = 1 and dc.answer_id = q.acceptedanswerid then 1 else 0 end) as accepted_is_top
    from posts q
    left join dup_clusters dc on dc.original_qid = q.id
    where q.posttypeid = 1
      and q.creationdate >= now() - interval '365 days'
    group by q.id, q.acceptedanswerid
),
activity_rank as (
    select
        ps.*,
        cs.comment_count,
        cs.positive_comments,
        cs.last_comment_at,
        cs.avg_comment_len,
        ee.edit_count,
        ee.last_edit_at,
        ee.had_moderation,
        lk.linked_count,
        lk.duplicate_count,
        lk.last_link_at,
        tq.tag_count,
        tq.known_tags,
        tq.avg_tag_popularity,
        ub.total_badges,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        avs.accepted_is_top,
        avs.has_top_answer,
        /* composite scoring */
        (coalesce(ps.net_votes,0) * 3
         + coalesce(ps.favorites,0) * 2
         + coalesce(ps.bounty_sum,0) * 0.01
         + coalesce(cs.comment_count,0) * 0.5
         + coalesce(ee.edit_count,0) * 0.75
         + coalesce(lk.linked_count,0) * 1.25
         - coalesce(lk.duplicate_count,0) * 2
         + coalesce(case when ps.posttypeid = 1 then ps.answercount else 0 end,0) * 0.8
         + coalesce(case when avs.accepted_is_top = 1 then 2 else 0 end,0)
         + coalesce(ub.gold_badges,0) * 0.2
        ) as composite_score
    from post_scores ps
    left join comment_stats cs on cs.postid = ps.post_id
    left join edit_events ee on ee.postid = ps.post_id
    left join linking lk on lk.postid = ps.post_id
    left join tag_quality tq on tq.post_id = ps.post_id
    left join user_badges ub on ub.user_id = ps.owneruserid
    left join accepted_vs_top avs on avs.question_id = ps.post_id
),
post_dimensions as (
    select
        ar.*,
        case when ar.posttypeid = 1 then 'Question'
             when ar.posttypeid = 2 then 'Answer'
             else 'Other' end as post_type_name,
        case when ar.closeddate is not null then 1 else 0 end as is_closed,
        extract(epoch from (now() - ar.creationdate)) / 86400.0 as age_days,
        nullif(position('java' in lower(coalesce(ar.tags,''))),0) as has_java,
        nullif(position('python' in lower(coalesce(ar.tags,''))),0) as has_python,
        case
            when ar.location ~* '(us|united states|usa)' then 'US'
            when ar.location ~* '(india)' then 'IN'
            when ar.location ~* '(uk|united kingdom|england|scotland|wales)' then 'UK'
            when ar.location is null then 'Unknown'
            else 'Other'
        end as user_region
    from activity_rank ar
),
normalized as (
    select
        pd.*,
        /* window-based normalization for benchmarking */
        percentile_cont(0.5) within group (order by coalesce(pd.net_votes,0)) over () as median_votes,
        avg(coalesce(pd.net_votes,0)) over () as avg_votes,
        stddev_pop(coalesce(pd.net_votes,0)) over () as sd_votes,
        rank() over (order by pd.composite_score desc nulls last) as score_rank,
        dense_rank() over (partition by pd.post_type_name order by pd.composite_score desc nulls last) as rank_within_type,
        row_number() over (partition by pd.user_region order by pd.composite_score desc nulls last, pd.lastactivitydate desc nulls last) as regional_rownum,
        lag(pd.composite_score) over (order by pd.lastactivitydate) as prev_score,
        lead(pd.composite_score) over (order by pd.lastactivitydate) as next_score
    from post_dimensions pd
),
anomalies as (
    select
        n.*,
        case
            when n.sd_votes > 0 and (coalesce(n.net_votes,0) - n.avg_votes) / nullif(n.sd_votes,0) > 3 then 'HighOutlier'
            when n.sd_votes > 0 and (coalesce(n.net_votes,0) - n.avg_votes) / nullif(n.sd_votes,0) < -3 then 'LowOutlier'
            else 'Normal'
        end as vote_outlier_flag,
        case
            when n.is_closed = 1 and coalesce(n.net_votes,0) > coalesce(n.median_votes,0) then 'ClosedButPopular'
            when n.is_closed = 0 and coalesce(n.net_votes,0) < 0 then 'OpenButNegative'
            else 'Typical'
        end as status_flag
    from normalized n
),
user_activity_summary as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        avg(p.score) filter (where p.posttypeid in (1,2)) as avg_score,
        sum(case when p.communityowneddate is not null then 1 else 0 end) as wiki_contribs,
        max(p.lastactivitydate) as last_seen_post
    from users u
    left join posts p on p.owneruserid = u.id
        and p.creationdate >= now() - interval '365 days'
    group by u.id
),
final_enriched as (
    select
        a.*,
        uas.q_count,
        uas.a_count,
        uas.avg_score as user_avg_post_score,
        uas.wiki_contribs,
        uas.last_seen_post
    from anomalies a
    left join user_activity_summary uas on uas.user_id = a.owneruserid
),
rank_buckets as (
    select
        fe.*,
        width_bucket(fe.composite_score, min(fe.composite_score) over (), max(fe.composite_score) over (), 10) as score_decile,
        case
            when fe.age_days <= 1 then 'D1'
            when fe.age_days <= 7 then 'D7'
            when fe.age_days <= 30 then 'D30'
            when fe.age_days <= 90 then 'D90'
            else 'D365'
        end as recency_bucket
    from final_enriched fe
)
select
    rb.post_id,
    rb.post_type_name,
    rb.title,
    rb.owner_name,
    coalesce(rb.location, 'Unknown') as owner_location,
    rb.user_region,
    rb.reputation,
    rb.viewcount,
    rb.net_votes,
    rb.favorites,
    rb.bounty_sum,
    rb.comment_count,
    rb.edit_count,
    rb.linked_count,
    rb.duplicate_count,
    rb.tag_count,
    round(coalesce(rb.avg_tag_popularity,0)::numeric, 3) as avg_tag_popularity,
    rb.accepted_is_top,
    rb.has_top_answer,
    rb.total_badges,
    rb.gold_badges,
    rb.silver_badges,
    rb.bronze_badges,
    rb.q_count,
    rb.a_count,
    round(coalesce(rb.user_avg_post_score,0)::numeric, 2) as user_avg_post_score,
    rb.wiki_contribs,
    rb.is_closed,
    rb.vote_outlier_flag,
    rb.status_flag,
    round(rb.composite_score::numeric,2) as composite_score,
    rb.score_rank,
    rb.rank_within_type,
    rb.regional_rownum,
    rb.score_decile,
    rb.recency_bucket,
    rb.creationdate,
    rb.lastactivitydate,
    rb.last_edit_at,
    rb.last_comment_at,
    rb.last_link_at,
    case when rb.has_java is not null then 1 else 0 end as has_java_tag,
    case when rb.has_python is not null then 1 else 0 end as has_python_tag
from rank_buckets rb
where
    -- complex predicate mixing null logic, subqueries, and expressions
    coalesce(rb.net_votes,0) + coalesce(rb.favorites,0) + (coalesce(rb.comment_count,0) / 2.0) > (
        select avg(coalesce(ps.net_votes,0) + coalesce(ps.favorites,0) + coalesce(cs.comment_count,0)/2.0)
        from post_scores ps
        left join comment_stats cs on cs.postid = ps.post_id
    )
    and (rb.is_closed = 0 or rb.duplicate_count = 0 or rb.vote_outlier_flag = 'HighOutlier')
    and (
        rb.post_type_name in ('Question','Answer')
        or (rb.tag_count is not null and rb.tag_count >= 1)
    )
    and (
        rb.owneruserid is null
        or exists (
            select 1
            from badges b
            where b.userid = rb.owneruserid
              and b.class in (1,2)
              and b.date >= now() - interval '730 days'
        )
    )
order by rb.score_decile desc, rb.composite_score desc, rb.lastactivitydate desc
limit 250;