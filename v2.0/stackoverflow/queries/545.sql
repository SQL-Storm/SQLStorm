-- {"query": "545.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2768}
with recent_activity as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid,
        coalesce(u.displayname, p.ownerdisplayname, 'anonymous') as owner_name,
        p.creationdate,
        p.lastactivitydate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        u.reputation,
        u.location,
        date_trunc('month', p.creationdate) as created_month
    from posts p
    left join users u on u.id = p.owneruserid
    where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
tag_expanded as (
    select
        ra.*,
        unnest(string_to_array(substring(ra.tags from 2 for length(ra.tags)-2), '><')) as tag_name
    from recent_activity ra
    where ra.posttypeid = 1
      and ra.tags is not null
),
votes_agg as (
    select
        v.postid,
        sum(case when vt.name = 'UpMod' then 1 else 0 end) as upvotes,
        sum(case when vt.name = 'DownMod' then 1 else 0 end) as downvotes,
        sum(case when vt.name = 'Favorite' then 1 else 0 end) as favorites,
        sum(case when vt.name = 'BountyStart' then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when vt.name = 'BountyClose' then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        min(v.creationdate) as first_vote_at,
        max(v.creationdate) as last_vote_at
    from votes v
    join votetypes vt on vt.id = v.votetypeid
    group by v.postid
),
comment_stats as (
    select
        c.postid,
        count(*) as comment_count,
        avg(nullif(c.score,0)) filter (where c.score is not null) as avg_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
post_edits as (
    select
        ph.postid,
        count(*) filter (where pht.name in ('Edit Title','Edit Body','Edit Tags')) as edit_count,
        count(*) filter (where pht.name = 'Post Closed') as close_events,
        count(*) filter (where pht.name = 'Post Reopened') as reopen_events,
        max(ph.creationdate) filter (where pht.name in ('Edit Title','Edit Body','Edit Tags')) as last_edit_date
    from posthistory ph
    join posthistorytypes pht on pht.id = ph.posthistorytypeid
    group by ph.postid
),
duplicates as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as canonical_post_id,
        min(pl.creationdate) as first_dup_link
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
    where lt.name = 'Duplicate'
    group by pl.postid, pl.relatedpostid
),
answer_perf as (
    select
        a.parentid as question_id,
        count(*) as answers,
        avg(a.score) as avg_answer_score,
        max(a.score) as max_answer_score,
        min(a.creationdate) as first_answer_time,
        max(a.creationdate) as last_answer_time
    from posts a
    where a.posttypeid = 2
    group by a.parentid
),
accepted_answer as (
    select
        q.id as question_id,
        a.id as answer_id,
        a.score as accepted_score,
        a.creationdate as accepted_time
    from posts q
    left join posts a on a.id = q.acceptedanswerid
),
user_badge_strength as (
    select
        b.userid,
        sum(case b.class when 1 then 9 when 2 then 3 when 3 then 1 else 0 end) as badge_weight,
        count(*) filter (where b.tagbased = true) as tag_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
monthly_tag_stats as (
    select
        te.created_month,
        te.tag_name,
        count(*) as questions,
        avg(te.score) as avg_q_score,
        avg(te.viewcount) as avg_views,
        -- approximate p90 by using percentile_disc which is more widely supported, without OVER()
        percentile_disc(0.9) within group (order by te.viewcount) as p90_views
    from tag_expanded te
    group by te.created_month, te.tag_name
),
ranked_questions as (
    select
        ra.post_id,
        ra.posttypeid,
        ra.owneruserid,
        ra.owner_name,
        ra.creationdate,
        ra.lastactivitydate,
        ra.score,
        ra.viewcount,
        ra.title,
        ra.tags,
        ra.answercount,
        ra.reputation,
        ra.location,
        ra.created_month,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as favorites,
        coalesce(va.bounty_started,0) as bounty_started,
        coalesce(va.bounty_awarded,0) as bounty_awarded,
        cs.comment_count,
        cs.avg_comment_score,
        cs.last_comment_date,
        pe.edit_count,
        pe.close_events,
        pe.reopen_events,
        pe.last_edit_date,
        ap.answers,
        ap.avg_answer_score,
        ap.max_answer_score,
        ap.first_answer_time,
        ap.last_answer_time,
        aa.answer_id as accepted_answer_id,
        aa.accepted_score,
        aa.accepted_time,
        case when d.dup_post_id is not null then 1 else 0 end as is_duplicate,
        dense_rank() over (partition by date_trunc('month', ra.creationdate) order by ra.viewcount desc nulls last) as monthly_view_rank,
        row_number() over (order by ra.score desc nulls last, coalesce(va.upvotes,0) - coalesce(va.downvotes,0) desc, ra.viewcount desc nulls last) as global_score_rank
    from recent_activity ra
    left join votes_agg va on va.postid = ra.post_id
    left join comment_stats cs on cs.postid = ra.post_id
    left join post_edits pe on pe.postid = ra.post_id
    left join answer_perf ap on ap.question_id = ra.post_id
    left join accepted_answer aa on aa.question_id = ra.post_id
    left join duplicates d on d.dup_post_id = ra.post_id
    where ra.posttypeid = 1
),
user_enriched as (
    select
        rq.post_id,
        rq.posttypeid,
        rq.owneruserid,
        rq.owner_name,
        rq.creationdate,
        rq.lastactivitydate,
        rq.score,
        rq.viewcount,
        rq.title,
        rq.tags,
        rq.answercount,
        rq.reputation,
        rq.location,
        rq.created_month,
        rq.upvotes,
        rq.downvotes,
        rq.favorites,
        rq.bounty_started,
        rq.bounty_awarded,
        rq.comment_count,
        rq.avg_comment_score,
        rq.last_comment_date,
        rq.edit_count,
        rq.close_events,
        rq.reopen_events,
        rq.last_edit_date,
        rq.answers,
        rq.avg_answer_score,
        rq.max_answer_score,
        rq.first_answer_time,
        rq.last_answer_time,
        rq.accepted_answer_id,
        rq.accepted_score,
        rq.accepted_time,
        rq.is_duplicate,
        rq.monthly_view_rank,
        rq.global_score_rank,
        ub.badge_weight,
        ub.tag_badges,
        ub.last_badge_date,
        u.websiteurl,
        u.upvotes as user_upvotes,
        u.downvotes as user_downvotes,
        u.views as profile_views
    from ranked_questions rq
    left join users u on u.id = rq.owneruserid
    left join user_badge_strength ub on ub.userid = rq.owneruserid
),
top_tags_per_month as (
    select
        mts.created_month,
        mts.tag_name,
        mts.questions,
        row_number() over (partition by mts.created_month order by mts.questions desc, mts.avg_q_score desc) as tag_rank
    from monthly_tag_stats mts
),
question_tag_agg as (
    select
        te.post_id,
        array_agg(distinct te.tag_name order by te.tag_name) as tags_array,
        string_agg(distinct te.tag_name, ', ' order by te.tag_name) as tags_csv
    from tag_expanded te
    group by te.post_id
),
final_scored as (
    select
        ue.post_id,
        ue.posttypeid,
        ue.owneruserid,
        ue.owner_name,
        ue.creationdate,
        ue.lastactivitydate,
        ue.score,
        ue.viewcount,
        ue.title,
        ue.tags,
        ue.answercount,
        ue.reputation,
        ue.location,
        ue.created_month,
        ue.upvotes,
        ue.downvotes,
        ue.favorites,
        ue.bounty_started,
        ue.bounty_awarded,
        ue.comment_count,
        ue.avg_comment_score,
        ue.last_comment_date,
        ue.edit_count,
        ue.close_events,
        ue.reopen_events,
        ue.last_edit_date,
        ue.answers,
        ue.avg_answer_score,
        ue.max_answer_score,
        ue.first_answer_time,
        ue.last_answer_time,
        ue.accepted_answer_id,
        ue.accepted_score,
        ue.accepted_time,
        ue.is_duplicate,
        ue.monthly_view_rank,
        ue.global_score_rank,
        ue.badge_weight,
        ue.tag_badges,
        ue.last_badge_date,
        ue.websiteurl,
        ue.user_upvotes,
        ue.user_downvotes,
        ue.profile_views,
        qta.tags_array,
        qta.tags_csv,
        coalesce((
            select avg(rq2.viewcount)
            from ranked_questions rq2
            where rq2.owneruserid = ue.owneruserid
              and rq2.creationdate >= ue.creationdate - interval '180 days'
              and rq2.creationdate < ue.creationdate
        ), 0) as trailing_6mo_author_avg_views,
        coalesce((
            select avg(rq3.score)
            from ranked_questions rq3
            where rq3.owneruserid = ue.owneruserid
              and rq3.creationdate >= ue.creationdate - interval '180 days'
              and rq3.creationdate < ue.creationdate
        ), 0) as trailing_6mo_author_avg_score,
        case
            when ue.is_duplicate = 1 then -100
            else
                (coalesce(ue.score,0) * 5)
              + (coalesce(ue.upvotes,0) * 3)
              - (coalesce(ue.downvotes,0) * 4)
              + (coalesce(ue.viewcount,0) / 50.0)
              + (coalesce(ue.favorites,0) * 8)
              + (coalesce(ue.bounty_awarded,0) / 10.0)
              + (coalesce(ue.answers,0) * 2)
              + (case when ue.accepted_answer_id is not null then 25 else 0 end)
              + (least(greatest(coalesce(ue.avg_answer_score,0), -5), 10) * 2)
              + (coalesce(ue.badge_weight,0) * 0.5)
              + (case when ue.edit_count > 5 then -10 else 0 end)
              + (case when ue.close_events > 0 then -20 else 0 end)
              + (case when ue.reopen_events > 0 then 5 else 0 end)
              + (case when ue.monthly_view_rank <= 10 then (20 - ue.monthly_view_rank) else 0 end)
              + (case when ue.global_score_rank <= 100 then (110 - ue.global_score_rank) else 0 end)
        end as composite_score
    from user_enriched ue
    left join question_tag_agg qta on qta.post_id = ue.post_id
),
merged_top as (
    select
        fs.*,
        ttm.tag_name as top_tag_for_month,
        ttm.questions as top_tag_monthly_qs
    from final_scored fs
    left join top_tags_per_month ttm
      on ttm.created_month = date_trunc('month', fs.creationdate)
     and ttm.tag_rank = 1
),
-- replace ordered-set percentile_cont(...) OVER() with a windowed median computed via percentile_disc()
normed as (
    select
        m.*,
        avg(m.composite_score) over () as avg_score_all,
        stddev_pop(m.composite_score) over () as sd_score_all,
        -- compute median using percentile_disc in a separate aggregation joined back to each row
        md.median_score_all
    from merged_top m
    cross join lateral (
        select percentile_disc(0.5) within group (order by composite_score) as median_score_all
        from merged_top
    ) md
),
flagged as (
    select
        n.*,
        case when n.composite_score > n.avg_score_all + 2 * nullif(n.sd_score_all,0) then 1 else 0 end as is_outlier_high,
        case when n.composite_score < n.avg_score_all - 2 * nullif(n.sd_score_all,0) then 1 else 0 end as is_outlier_low
    from normed n
)
select
    f.post_id,
    coalesce(f.title, '(no title)') as title,
    f.owner_name,
    f.reputation,
    f.location,
    f.creationdate,
    f.lastactivitydate,
    f.viewcount,
    f.score,
    f.upvotes,
    f.downvotes,
    f.favorites,
    f.bounty_started,
    f.bounty_awarded,
    f.answercount,
    f.answers,
    f.accepted_answer_id,
    f.accepted_score,
    f.edit_count,
    f.close_events,
    f.reopen_events,
    f.comment_count,
    round(coalesce(f.avg_comment_score,0), 2) as avg_comment_score,
    f.tags_csv,
    f.top_tag_for_month,
    f.top_tag_monthly_qs,
    f.monthly_view_rank,
    f.global_score_rank,
    round(cast(f.composite_score as numeric), 2) as composite_score,
    round(cast((f.composite_score - f.avg_score_all) as numeric), 2) as score_diff_from_avg,
    f.is_outlier_high,
    f.is_outlier_low,
    f.trailing_6mo_author_avg_views,
    f.trailing_6mo_author_avg_score,
    case
        when f.is_duplicate = 1 then 'Duplicate'
        when f.close_events > 0 and f.reopen_events = 0 then 'Closed'
        when f.close_events > 0 and f.reopen_events > 0 then 'Closed/Reopened'
        else 'Open'
    end as status_label
from flagged f
where
    (f.viewcount > coalesce(f.trailing_6mo_author_avg_views,0) * 1.5 or f.is_outlier_high = 1)
    and coalesce(f.reputation,0) >= 1
order by f.composite_score desc nulls last, f.viewcount desc nulls last
limit 250;