-- {"query": "812.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3362} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        u.lastaccessdate,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.domain') as website_domain,
        row_number() over (order by u.reputation desc, u.id) as rn
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from users)
),
active_questions as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.tags,
        p.title,
        p.acceptedanswerid,
        p.closeddate,
        (case when p.closeddate is not null then 1 else 0 end) as is_closed,
        coalesce(p.viewcount, 0) + 10 * coalesce(p.favoritecount, 0) + 5 * coalesce(p.commentcount, 0) + 20 * case when p.acceptedanswerid is not null then 1 else 0 end as engagement_score
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '36 months' from posts)
),
question_badge_agg as (
    select
        aq.post_id,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges
    from active_questions aq
    left join badges b on b.userid = aq.user_id
    group by aq.post_id
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount, 0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount, 0) else 0 end) as bounty_awarded,
        count(*) filter (where v.votetypeid in (2,3)) as total_votes
    from votes v
    join active_questions aq on aq.post_id = v.postid
    group by v.postid
),
comment_sentiment as (
    select
        c.postid,
        avg(length(c.text)) as avg_comment_len,
        sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_count,
        sum(case when position('please' in lower(c.text)) > 0 then 1 else 0 end) as please_count,
        count(*) as comment_count
    from comments c
    join active_questions aq on aq.post_id = c.postid
    group by c.postid
),
tag_exploded as (
    select
        aq.post_id,
        unnest(string_to_array(substring(aq.tags, 2, greatest(length(aq.tags)-2,0)), '><')) as tag
    from active_questions aq
    where aq.tags is not null
),
top_tags as (
    select tag, count(*) as tag_count
    from tag_exploded
    group by tag
),
tag_rank as (
    select
        tt.tag,
        tt.tag_count,
        ntile(10) over (order by tt.tag_count desc) as tag_popularity_decile,
        dense_rank() over (order by tt.tag_count desc, tt.tag) as tag_global_rank
    from top_tags tt
),
question_tag_stats as (
    select
        te.post_id,
        max(tr.tag_popularity_decile) as max_tag_decile,
        min(tr.tag_popularity_decile) as min_tag_decile,
        avg(tr.tag_count::numeric) as avg_tag_count,
        sum(case when tr.tag_global_rank <= 100 then 1 else 0 end) as top100_tag_hits
    from tag_exploded te
    left join tag_rank tr on tr.tag = te.tag
    group by te.post_id
),
duplicates as (
    select
        pl.postid as dup_post_id,
        count(*) as dup_links,
        max(pl.creationdate) as last_dup_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid
),
linked_posts as (
    select
        pl.relatedpostid as related_post_id,
        count(*) filter (where pl.linktypeid = 1) as linked_in_count,
        count(*) filter (where pl.linktypeid = 3) as dup_of_count
    from postlinks pl
    group by pl.relatedpostid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_count,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_count,
        max(case when ph.posthistorytypeid = 10 then nullif(ph.comment, '') end) as last_close_reason_id_str
    from posthistory ph
    join active_questions aq on aq.post_id = ph.postid
    group by ph.postid
),
close_reason_lkp as (
    select
        crt.id::varchar as reason_id_str,
        crt.name as reason_name
    from closereasontypes crt
),
user_activity as (
    select
        u.id as user_id,
        count(distinct p.id) filter (where p.posttypeid = 1) as questions_count,
        count(distinct p.id) filter (where p.posttypeid = 2) as answers_count,
        sum(greatest(p.score,0)) as total_positive_score,
        avg(nullif(p.viewcount,0)) as avg_views_nonzero,
        max(p.creationdate) as last_post_date
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
user_quality_rank as (
    select
        ua.user_id,
        percent_rank() over (order by coalesce(ua.total_positive_score,0) desc, coalesce(ua.answers_count,0) desc, coalesce(ua.questions_count,0) desc) as quality_percentile
    from user_activity ua
),
question_core as (
    select
        aq.post_id,
        aq.user_id,
        aq.creationdate,
        aq.score,
        aq.viewcount,
        aq.engagement_score,
        qa.gold_badges,
        qa.silver_badges,
        qa.bronze_badges,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.total_votes,0) as total_votes,
        coalesce(va.bounty_started,0) as bounty_started,
        coalesce(va.bounty_awarded,0) as bounty_awarded,
        coalesce(cs.avg_comment_len,0) as avg_comment_len,
        coalesce(cs.thanks_count,0) as thanks_count,
        coalesce(cs.please_count,0) as please_count,
        coalesce(cs.comment_count,0) as comment_count,
        coalesce(qts.max_tag_decile,10) as max_tag_decile,
        coalesce(qts.min_tag_decile,10) as min_tag_decile,
        coalesce(qts.avg_tag_count,0) as avg_tag_count,
        coalesce(qts.top100_tag_hits,0) as top100_tag_hits,
        coalesce(d.dup_links,0) as dup_links,
        d.last_dup_link_date,
        coalesce(lp.linked_in_count,0) as linked_in_count,
        coalesce(lp.dup_of_count,0) as dup_of_count,
        ce.first_close_date,
        ce.last_reopen_date,
        ce.close_count,
        ce.reopen_count,
        ce.last_close_reason_id_str
    from active_questions aq
    left join question_badge_agg qa on qa.post_id = aq.post_id
    left join vote_agg va on va.postid = aq.post_id
    left join comment_sentiment cs on cs.postid = aq.post_id
    left join question_tag_stats qts on qts.post_id = aq.post_id
    left join duplicates d on d.dup_post_id = aq.post_id
    left join linked_posts lp on lp.related_post_id = aq.post_id
    left join close_events ce on ce.postid = aq.post_id
),
normalized as (
    select
        qc.*,
        nullif(qc.total_votes,0) as total_votes_nz,
        case when qc.total_votes > 0 then (qc.upvotes::numeric - qc.downvotes::numeric)/qc.total_votes::numeric else 0 end as vote_ratio,
        case when qc.viewcount > 0 then qc.engagement_score::numeric / qc.viewcount::numeric else 0 end as engagement_per_view,
        case when qc.comment_count > 0 then qc.avg_comment_len else 0 end as avg_len_if_comments
    from question_core qc
),
close_reason_join as (
    select
        n.*,
        cr.reason_name as last_close_reason_name
    from normalized n
    left join close_reason_lkp cr on cr.reason_id_str = n.last_close_reason_id_str
),
user_enriched as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.location,
        ru.website_domain,
        ua.questions_count,
        ua.answers_count,
        ua.total_positive_score,
        ua.avg_views_nonzero,
        ua.last_post_date,
        uqr.quality_percentile
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_quality_rank uqr on uqr.user_id = ru.user_id
),
scored as (
    select
        crj.post_id,
        crj.user_id,
        ue.displayname,
        ue.reputation,
        ue.location,
        ue.website_domain,
        ue.quality_percentile,
        crj.creationdate,
        crj.score,
        crj.viewcount,
        crj.upvotes,
        crj.downvotes,
        crj.vote_ratio,
        crj.engagement_score,
        crj.engagement_per_view,
        crj.gold_badges,
        crj.silver_badges,
        crj.bronze_badges,
        crj.max_tag_decile,
        crj.min_tag_decile,
        crj.top100_tag_hits,
        crj.dup_links,
        crj.linked_in_count,
        crj.dup_of_count,
        crj.close_count,
        crj.reopen_count,
        crj.first_close_date,
        crj.last_reopen_date,
        coalesce(crj.last_close_reason_name, 'Unknown') as last_close_reason_name,
        -- composite score with varied weights and null handling
        (
            0.30 * coalesce(crj.vote_ratio, 0) +
            0.20 * coalesce(crj.engagement_per_view, 0) +
            0.15 * (coalesce(ue.quality_percentile, 0)) +
            0.10 * (1 - (coalesce(crj.max_tag_decile,10)::numeric / 10)) +
            0.05 * greatest(least(coalesce(crj.top100_tag_hits,0), 3), 0) / 3.0 +
            0.10 * case when crj.dup_links = 0 then 1 else 0.5 end +
            0.05 * case when crj.close_count = 0 then 1 else 0.2 end +
            0.05 * case when crj.reopen_count > 0 then 0.8 else 0.5 end
        ) as composite_score
    from close_reason_join crj
    left join user_enriched ue on ue.user_id = crj.user_id
),
ranked as (
    select
        s.*,
        row_number() over (order by s.composite_score desc, s.viewcount desc, s.score desc, s.post_id) as rk,
        rank() over (order by s.composite_score desc) as rnk_ties,
        dense_rank() over (order by s.composite_score desc) as drnk,
        ntile(20) over (order by s.composite_score desc) as quantile20
    from scored s
),
banded as (
    select
        r.*,
        case
            when r.composite_score >= percentile_cont(0.95) within group (order by r.composite_score) over () then 'A+'
            when r.composite_score >= percentile_cont(0.80) within group (order by r.composite_score) over () then 'A'
            when r.composite_score >= percentile_cont(0.60) within group (order by r.composite_score) over () then 'B'
            when r.composite_score >= percentile_cont(0.40) within group (order by r.composite_score) over () then 'C'
            when r.composite_score >= percentile_cont(0.20) within group (order by r.composite_score) over () then 'D'
            else 'E'
        end as perf_band
    from ranked r
),
final_set as (
    select * from banded where perf_band in ('A+','A')
    union all
    select * from banded where perf_band = 'B' and max_tag_decile <= 5
    union all
    select * from banded where perf_band in ('C','D','E') and composite_score > (
        select avg(composite_score) from banded
    )
)
select
    fs.rk,
    fs.post_id,
    fs.displayname,
    fs.reputation,
    fs.location,
    fs.website_domain,
    fs.creationdate,
    fs.score,
    fs.viewcount,
    fs.upvotes,
    fs.downvotes,
    round(fs.vote_ratio::numeric, 4) as vote_ratio,
    round(fs.engagement_per_view::numeric, 4) as engagement_per_view,
    fs.gold_badges,
    fs.silver_badges,
    fs.bronze_badges,
    fs.max_tag_decile,
    fs.min_tag_decile,
    fs.top100_tag_hits,
    fs.dup_links,
    fs.linked_in_count,
    fs.dup_of_count,
    fs.close_count,
    fs.reopen_count,
    coalesce(to_char(fs.first_close_date, 'YYYY-MM-DD"T"HH24:MI:SS'), 'N/A') as first_close_date,
    coalesce(to_char(fs.last_reopen_date, 'YYYY-MM-DD"T"HH24:MI:SS'), 'N/A') as last_reopen_date,
    fs.last_close_reason_name,
    round(fs.composite_score::numeric, 6) as composite_score,
    fs.perf_band,
    fs.quantile20
from final_set fs
where not (
    fs.location is null and fs.website_domain = 'unknown.domain'
)
order by fs.composite_score desc, fs.viewcount desc, fs.score desc, fs.post_id
limit 250;