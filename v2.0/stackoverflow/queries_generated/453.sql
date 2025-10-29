-- {"query": "453.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2908} 
with params as (
    select
        365::int as lookback_days,
        0.25::numeric as low_rep_pct,
        0.75::numeric as high_rep_pct
),
active_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        row_number() over (order by u.reputation desc, u.id) as rep_rank,
        ntile(100) over (order by u.reputation) as rep_percentile
    from users u
),
rep_bounds as (
    select
        percentile_disc(p.low_rep_pct) within group (order by reputation) as low_rep_cut,
        percentile_disc(p.high_rep_pct) within group (order by reputation) as high_rep_cut
    from users, params p
),
recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.parentid
    from posts p
    cross join params prm
    where p.creationdate >= now() - (prm.lookback_days || ' days')::interval
),
questions as (
    select rp.*
    from recent_posts rp
    where rp.posttypeid = 1
),
answers as (
    select rp.*
    from recent_posts rp
    where rp.posttypeid = 2
),
tag_array as (
    select
        q.id as question_id,
        string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><') as tags
    from questions q
),
tag_expanded as (
    select
        question_id,
        lower(trim(t)) as tag
    from tag_array
    cross join lateral unnest(tags) as t
),
tag_stats as (
    select
        te.tag,
        count(*) as q_count,
        count(*) filter (where coalesce(q.score,0) > 0) as q_positive,
        avg(q.score::numeric) as avg_q_score,
        avg(nullif(q.viewcount,0)) as avg_q_views
    from tag_expanded te
    join questions q on q.id = te.question_id
    group by te.tag
),
post_interactions as (
    select
        rp.id as post_id,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
        count(*) filter (where v.votetypeid = 5) as favorites,
        count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
        max(v.bountyamount) filter (where v.votetypeid in (8,9)) as max_bounty
    from recent_posts rp
    left join votes v on v.postid = rp.id
    group by rp.id
),
comment_agg as (
    select
        c.postid,
        count(*) as comment_ct,
        max(c.score) as max_comment_score,
        min(c.score) as min_comment_score,
        string_agg(distinct coalesce(nullif(c.userdisplayname,''), 'anon'), ', ' order by coalesce(nullif(c.userdisplayname,''), 'anon')) as commenters
    from comments c
    where c.creationdate >= (select now() - (lookback_days || ' days')::interval from params)
    group by c.postid
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as orig_post_id,
        min(pl.creationdate) as first_dup_link_at,
        count(*) as dup_link_ct
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
ph_close as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max(nullif(ph.comment,'')::int) filter (where ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$') as last_close_reason_id
    from posthistory ph
    join questions q on q.id = ph.postid
    group by ph.postid
),
accepted_answer as (
    select
        q.id as question_id,
        a.id as answer_id,
        a.owneruserid as answer_owner_id,
        a.score as answer_score,
        a.creationdate as answer_created_at
    from questions q
    left join posts a on a.id = q.acceptedanswerid
),
answer_summaries as (
    select
        q.id as question_id,
        count(a.id) as answer_ct,
        coalesce(sum(a.score),0) as sum_answer_scores,
        max(a.score) as max_answer_score,
        min(a.score) as min_answer_score
    from questions q
    left join answers a on a.parentid = q.id
    group by q.id
),
user_segments as (
    select
        au.id as user_id,
        case
            when au.reputation <= rb.low_rep_cut then 'low'
            when au.reputation >= rb.high_rep_cut then 'high'
            else 'mid'
        end as rep_band,
        au.rep_percentile,
        au.rep_rank
    from active_users au
    cross join rep_bounds rb
),
question_owner_seg as (
    select
        q.id as question_id,
        us.rep_band as owner_rep_band,
        us.rep_percentile as owner_rep_pct,
        us.rep_rank as owner_rep_rank
    from questions q
    left join user_segments us on us.user_id = q.owneruserid
),
word_count as (
    select
        q.id as question_id,
        coalesce(array_length(regexp_split_to_array(regexp_replace(coalesce(q.title,''), '\s+', ' ', 'g'), '\s'),1),0) as title_words,
        length(coalesce(q.body,'')) as body_len
    from questions q
),
ranked_questions as (
    select
        q.id as question_id,
        q.owneruserid,
        q.creationdate,
        q.score,
        q.viewcount,
        q.favoritecount,
        qa.answer_ct,
        pi.net_votes,
        pi.favorites as vote_favorites,
        coalesce(pi.max_bounty,0) as max_bounty,
        ws.title_words,
        ws.body_len,
        row_number() over (partition by coalesce(q.owneruserid,-1) order by coalesce(q.viewcount,0) desc, q.score desc, q.id) as rn_by_owner_views,
        dense_rank() over (order by coalesce(q.viewcount,0) desc) as dense_rank_views,
        percentile_cont(0.9) within group (order by coalesce(q.viewcount,0)) over () as p90_views
    from questions q
    left join answer_summaries qa on qa.question_id = q.id
    left join post_interactions pi on pi.post_id = q.id
    left join word_count ws on ws.question_id = q.id
),
owner_activity as (
    select
        u.id as user_id,
        count(distinct q.id) as q_count,
        count(distinct a.id) as a_count,
        sum(coalesce(q.score,0)) as q_score_sum,
        sum(coalesce(a.score,0)) as a_score_sum,
        sum(case when q.creationdate >= now() - interval '30 days' then 1 else 0 end) as q_30d_ct
    from users u
    left join questions q on q.owneruserid = u.id
    left join answers a on a.owneruserid = u.id
    group by u.id
),
flag_hot as (
    select
        rq.question_id,
        case when rq.viewcount >= rq.p90_views and rq.score >= 5 then 1 else 0 end as is_hot_candidate
    from ranked_questions rq
),
final_scores as (
    select
        q.id as question_id,
        coalesce(qs.owner_rep_band,'unknown') as owner_rep_band,
        coalesce(ta.tag, '(no-tag)') as sample_tag,
        q.title,
        q.creationdate,
        q.viewcount,
        q.score,
        qa.answer_ct,
        aa.answer_id as accepted_answer_id,
        aa.answer_score as accepted_answer_score,
        pi.net_votes,
        coalesce(pi.favorites,0) as vote_favorites,
        coalesce(ca.comment_ct,0) as comment_ct,
        coalesce(ca.max_comment_score,0) as max_comment_score,
        coalesce(phc.close_events,0) as close_events,
        coalesce(phc.reopen_events,0) as reopen_events,
        phc.last_close_reason_id,
        dl.dup_link_ct,
        case when dl.dup_post_id is not null then 1 else 0 end as is_marked_duplicate,
        fs.is_hot_candidate,
        -- composite score with NULL and boundary handling
        (
            coalesce(q.score,0)::numeric * 2
            + least(greatest(coalesce(q.viewcount,0)::numeric / nullif(greatest(ts.avg_q_views,1),0), 0), 10)
            + coalesce(qa.answer_ct,0) * 0.5
            + coalesce(pi.net_votes,0) * 1.25
            + case when phc.close_events > 0 then -5 else 0 end
            + case when fs.is_hot_candidate = 1 then 7.5 else 0 end
            - case when dl.dup_post_id is not null then 3 else 0 end
        ) as composite_score
    from questions q
    left join question_owner_seg qs on qs.question_id = q.id
    left join tag_expanded te on te.question_id = q.id
    left join lateral (select te2.tag from tag_expanded te2 where te2.question_id = q.id order by te2.tag limit 1) ta on true
    left join tag_stats ts on ts.tag = ta.tag
    left join answer_summaries qa on qa.question_id = q.id
    left join accepted_answer aa on aa.question_id = q.id
    left join post_interactions pi on pi.post_id = q.id
    left join comment_agg ca on ca.postid = q.id
    left join ph_close phc on phc.postid = q.id
    left join dup_links dl on dl.dup_post_id = q.id
    left join flag_hot fs on fs.question_id = q.id
),
owner_enrichment as (
    select
        q.id as question_id,
        u.id as owner_id,
        coalesce(u.displayname, '(deleted)') as owner_name,
        u.reputation as owner_rep,
        us.rep_band as owner_band,
        oa.q_count as owner_q_count,
        oa.a_count as owner_a_count,
        oa.q_30d_ct as owner_q_30d_ct,
        rank() over (order by u.reputation desc nulls last) as owner_rep_rank_global
    from questions q
    left join users u on u.id = q.owneruserid
    left join user_segments us on us.user_id = u.id
    left join owner_activity oa on oa.user_id = u.id
)
select
    fs.question_id,
    oe.owner_id,
    oe.owner_name,
    oe.owner_rep,
    fs.owner_rep_band,
    fs.sample_tag,
    fs.title,
    fs.creationdate,
    fs.viewcount,
    fs.score,
    fs.answer_ct,
    fs.accepted_answer_id,
    fs.accepted_answer_score,
    fs.net_votes,
    fs.vote_favorites,
    fs.comment_ct,
    fs.max_comment_score,
    fs.close_events,
    fs.reopen_events,
    fs.last_close_reason_id,
    fs.dup_link_ct,
    fs.is_hot_candidate,
    oe.owner_q_count,
    oe.owner_a_count,
    oe.owner_q_30d_ct,
    oe.owner_rep_rank_global,
    fs.composite_score,
    -- string and NULL logic showcase
    trim(both ' ' from coalesce(substring(fs.title from 1 for 120), '(no title)')) || ' — ' ||
    coalesce(initcap(replace(oe.owner_name, '_', ' ')), 'unknown') || ' [' ||
    coalesce(fs.sample_tag,'none') || ']' as preview
from final_scores fs
left join owner_enrichment oe on oe.question_id = fs.question_id
where
    (
        fs.owner_rep_band in ('low','high')
        or fs.is_hot_candidate = 1
        or fs.close_events > 0
        or fs.dup_link_ct is not null
    )
    and (fs.viewcount is distinct from null and fs.viewcount >= 0)
    and not (fs.score is null and fs.answer_ct is null)
qualify row_number() over (
    partition by coalesce(oe.owner_id,-1)
    order by fs.composite_score desc, fs.viewcount desc, fs.question_id
) <= 50
order by fs.composite_score desc, fs.viewcount desc, fs.question_id
limit 500;