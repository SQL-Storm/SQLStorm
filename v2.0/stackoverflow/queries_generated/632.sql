-- {"query": "632.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3764} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        dense_rank() over (order by u.creationdate desc) as recency_rank
    from users u
),
top_recent as (
    select ru.*
    from recent_users ru
    where ru.recency_rank <= 500
),
user_posts as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.title,
        p.tags,
        coalesce(p.favoritecount, 0) as favoritecount,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.owneruserid is not null
),
user_activity as (
    select
        tr.user_id,
        count(*) filter (where up.posttypeid = 1) as q_count,
        count(*) filter (where up.posttypeid = 2) as a_count,
        sum(coalesce(up.score, 0)) as total_score,
        sum(coalesce(up.viewcount, 0)) as total_views,
        sum(coalesce(up.favoritecount, 0)) as total_faves,
        sum(coalesce(up.answercount, 0)) filter (where up.posttypeid = 1) as total_answers_on_questions,
        max(up.creationdate) as last_post_date,
        min(up.creationdate) as first_post_date,
        count(*) filter (where up.is_closed = 1) as closed_posts
    from top_recent tr
    left join user_posts up on up.user_id = tr.user_id
    group by tr.user_id
),
votes_agg as (
    select
        tr.user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_received,
        count(*) filter (where v.votetypeid = 3) as downvotes_received,
        count(*) filter (where v.votetypeid = 8) as bounty_start,
        count(*) filter (where v.votetypeid = 9) as bounty_close,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_amount_total
    from top_recent tr
    left join posts p on p.owneruserid = tr.user_id
    left join votes v on v.postid = p.id
    group by tr.user_id
),
badges_agg as (
    select
        tr.user_id,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges,
        count(*) filter (where b.tagbased = 0) as named_badges,
        max(b.date) as last_badge_date
    from top_recent tr
    left join badges b on b.userid = tr.user_id
    group by tr.user_id
),
comments_agg as (
    select
        tr.user_id,
        count(c.id) as comments_made,
        sum(coalesce(c.score, 0)) as comment_score_sum,
        max(c.creationdate) as last_comment_date
    from top_recent tr
    left join comments c on c.userid = tr.user_id
    group by tr.user_id
),
links_agg as (
    select
        tr.user_id,
        count(pl.id) filter (where pl.linktypeid = 1) as linked_refs,
        count(pl.id) filter (where pl.linktypeid = 3) as duplicate_links
    from top_recent tr
    left join posts p on p.owneruserid = tr.user_id
    left join postlinks pl on pl.postid = p.id
    group by tr.user_id
),
edits_agg as (
    select
        tr.user_id,
        count(ph.id) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
        count(ph.id) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_state_events,
        max(ph.creationdate) as last_edit_date
    from top_recent tr
    left join posts p on p.owneruserid = tr.user_id
    left join posthistory ph on ph.postid = p.id
    group by tr.user_id
),
tag_exploded as (
    select
        up.user_id,
        lower(trim(tag)) as tag
    from user_posts up
    join top_recent tr on tr.user_id = up.user_id
    cross join lateral (
        select unnest(string_to_array(substring(coalesce(up.tags, ''), 2, greatest(length(coalesce(up.tags, ''))-2, 0)), '><')) as tag
    ) t
),
tag_pref as (
    select
        te.user_id,
        array_agg(tag order by cnt desc, tag) filter (where cnt > 0) as top_tags,
        max(cnt) as top_tag_count
    from (
        select te.user_id, te.tag, count(*) as cnt
        from tag_exploded te
        group by te.user_id, te.tag
    ) s
    group by te.user_id
),
question_answer_ratio as (
    select
        ua.user_id,
        case
            when (ua.q_count is null and ua.a_count is null) then null
            when coalesce(ua.a_count,0) = 0 and coalesce(ua.q_count,0) = 0 then null
            when coalesce(ua.q_count,0) = 0 then null
            else round(coalesce(ua.a_count,0)::numeric / nullif(ua.q_count,0), 4)
        end as a_per_q
    from user_activity ua
),
hot_questions as (
    select
        p.owneruserid as user_id,
        count(*) as hot_qs
    from posts p
    where p.posttypeid = 1
      and p.viewcount >= (
          select percentile_disc(0.95) within group (order by coalesce(viewcount,0))
          from posts
          where posttypeid = 1
      )
    group by p.owneruserid
),
accepted_answers as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_answers
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
      and a.posttypeid = 2
    group by a.owneruserid
),
first_last_gap as (
    select
        ua.user_id,
        extract(epoch from (ua.last_post_date - ua.first_post_date)) / 86400.0 as active_days_span
    from user_activity ua
),
activity_streaks as (
    select
        tr.user_id,
        max(consecutive_days) as max_daily_streak
    from top_recent tr
    left join lateral (
        select
            count(*) as consecutive_days
        from (
            select
                date_trunc('day', p.creationdate) as d,
                row_number() over (order by date_trunc('day', p.creationdate)) as rn
            from posts p
            where p.owneruserid = tr.user_id
            group by date_trunc('day', p.creationdate)
        ) x
        group by (d - (rn || ' days')::interval)
    ) streaks on true
    group by tr.user_id
),
rankings as (
    select
        tr.user_id,
        dense_rank() over (order by coalesce(ua.total_score,0) desc, coalesce(va.upvotes_received,0) desc) as score_rank,
        dense_rank() over (order by coalesce(ua.total_views,0) desc) as views_rank,
        dense_rank() over (order by coalesce(bd.gold_badges,0) desc, coalesce(bd.silver_badges,0) desc, coalesce(bd.bronze_badges,0) desc) as badges_rank
    from top_recent tr
    left join user_activity ua on ua.user_id = tr.user_id
    left join votes_agg va on va.user_id = tr.user_id
    left join badges_agg bd on bd.user_id = tr.user_id
),
quality_signals as (
    select
        tr.user_id,
        coalesce(aa.accepted_answers,0) as accepted_answers,
        coalesce(hq.hot_qs,0) as hot_questions,
        coalesce(va.upvotes_received,0) - coalesce(va.downvotes_received,0) as net_votes,
        coalesce(ua.total_score,0) as total_post_score
    from top_recent tr
    left join accepted_answers aa on aa.user_id = tr.user_id
    left join hot_questions hq on hq.user_id = tr.user_id
    left join votes_agg va on va.user_id = tr.user_id
    left join user_activity ua on ua.user_id = tr.user_id
),
norms as (
    select
        tr.user_id,
        -- z-score style normalization using window stats
        case
            when stddev_pop(coalesce(ua.total_score,0)) over () = 0 then 0
            else (coalesce(ua.total_score,0) - avg(coalesce(ua.total_score,0)) over ()) / nullif(stddev_pop(coalesce(ua.total_score,0)) over (),0)
        end as z_total_score,
        case
            when stddev_pop(coalesce(va.upvotes_received,0)) over () = 0 then 0
            else (coalesce(va.upvotes_received,0) - avg(coalesce(va.upvotes_received,0)) over ()) / nullif(stddev_pop(coalesce(va.upvotes_received,0)) over (),0)
        end as z_upvotes,
        case
            when stddev_pop(coalesce(ua.total_views,0)) over () = 0 then 0
            else (coalesce(ua.total_views,0) - avg(coalesce(ua.total_views,0)) over ()) / nullif(stddev_pop(coalesce(ua.total_views,0)) over (),0)
        end as z_views
    from top_recent tr
    left join user_activity ua on ua.user_id = tr.user_id
    left join votes_agg va on va.user_id = tr.user_id
),
final_scores as (
    select
        tr.user_id,
        0.4 * coalesce(n.z_total_score, 0) +
        0.35 * coalesce(n.z_upvotes, 0) +
        0.25 * coalesce(n.z_views, 0) +
        0.05 * greatest(0, coalesce(qr.a_per_q, 0)) +
        0.05 * least(1.0, coalesce(qa.accepted_answers,0) / nullif(coalesce(ua.a_count,0), 0)::numeric) as composite_score
    from top_recent tr
    left join norms n on n.user_id = tr.user_id
    left join question_answer_ratio qr on qr.user_id = tr.user_id
    left join quality_signals qa on qa.user_id = tr.user_id
    left join user_activity ua on ua.user_id = tr.user_id
),
dup_network as (
    select
        tr.user_id,
        count(distinct pl.relatedpostid) as distinct_duplicates_related
    from top_recent tr
    left join posts p on p.owneruserid = tr.user_id
    left join postlinks pl on pl.postid = p.id and pl.linktypeid = 3
    group by tr.user_id
),
user_title_snippets as (
    select
        tr.user_id,
        string_agg(
            left(coalesce(p.title, ''), 30),
            ' | ' order by p.score desc nulls last, p.viewcount desc nulls last
        ) as title_snippets
    from top_recent tr
    left join posts p on p.owneruserid = tr.user_id and p.posttypeid = 1
    group by tr.user_id
),
post_type_mix as (
    select
        tr.user_id,
        100.0 * sum(case when up.posttypeid = 1 then 1 else 0 end)::numeric / nullif(count(*),0) as pct_questions,
        100.0 * sum(case when up.posttypeid = 2 then 1 else 0 end)::numeric / nullif(count(*),0) as pct_answers
    from top_recent tr
    left join user_posts up on up.user_id = tr.user_id
    group by tr.user_id
),
null_logic_probe as (
    select
        tr.user_id,
        coalesce(nullif(bd.gold_badges, 0), -1) as gold_or_neg1,
        nullif(coalesce(ua.closed_posts, 0), 0) as closed_posts_or_null
    from top_recent tr
    left join badges_agg bd on bd.user_id = tr.user_id
    left join user_activity ua on ua.user_id = tr.user_id
),
string_flags as (
    select
        tr.user_id,
        case
            when position('http' in coalesce(u.websiteurl, '')) > 0 then 1 else 0
        end as has_http_website,
        case
            when coalesce(u.location, '') ilike any (array['%usa%','%united states%','%new york%','%san francisco%']) then 1 else 0
        end as likely_us_location
    from top_recent tr
    join users u on u.id = tr.user_id
)
select
    tr.user_id,
    tr.displayname,
    tr.reputation,
    tr.location,
    to_char(tr.creationdate, 'YYYY-MM-DD"T"HH24:MI:SS') as user_created_at,
    ua.q_count,
    ua.a_count,
    ua.total_score,
    ua.total_views,
    ua.total_faves,
    ua.total_answers_on_questions,
    ua.closed_posts,
    to_char(ua.last_post_date, 'YYYY-MM-DD') as last_post_date,
    to_char(ua.first_post_date, 'YYYY-MM-DD') as first_post_date,
    va.upvotes_received,
    va.downvotes_received,
    va.bounty_start,
    va.bounty_close,
    va.bounty_amount_total,
    bd.gold_badges,
    bd.silver_badges,
    bd.bronze_badges,
    bd.tag_badges,
    bd.named_badges,
    to_char(bd.last_badge_date, 'YYYY-MM-DD') as last_badge_date,
    ca.comments_made,
    ca.comment_score_sum,
    to_char(ca.last_comment_date, 'YYYY-MM-DD') as last_comment_date,
    la.linked_refs,
    la.duplicate_links,
    ea.edit_events,
    ea.mod_state_events,
    to_char(ea.last_edit_date, 'YYYY-MM-DD') as last_edit_date,
    tp.top_tags,
    tp.top_tag_count,
    qar.a_per_q,
    hq.hot_qs,
    aa.accepted_answers,
    flg.active_days_span,
    astr.max_daily_streak,
    rk.score_rank,
    rk.views_rank,
    rk.badges_rank,
    qs.net_votes,
    qs.total_post_score,
    round(fs.composite_score::numeric, 4) as composite_score,
    dn.distinct_duplicates_related,
    uts.title_snippets,
    ptm.pct_questions,
    ptm.pct_answers,
    nlp.gold_or_neg1,
    nlp.closed_posts_or_null,
    sf.has_http_website,
    sf.likely_us_location
from top_recent tr
left join user_activity ua on ua.user_id = tr.user_id
left join votes_agg va on va.user_id = tr.user_id
left join badges_agg bd on bd.user_id = tr.user_id
left join comments_agg ca on ca.user_id = tr.user_id
left join links_agg la on la.user_id = tr.user_id
left join edits_agg ea on ea.user_id = tr.user_id
left join tag_pref tp on tp.user_id = tr.user_id
left join question_answer_ratio qar on qar.user_id = tr.user_id
left join hot_questions hq on hq.user_id = tr.user_id
left join accepted_answers aa on aa.user_id = tr.user_id
left join first_last_gap flg on flg.user_id = tr.user_id
left join activity_streaks astr on astr.user_id = tr.user_id
left join rankings rk on rk.user_id = tr.user_id
left join quality_signals qs on qs.user_id = tr.user_id
left join final_scores fs on fs.user_id = tr.user_id
left join dup_network dn on dn.user_id = tr.user_id
left join user_title_snippets uts on uts.user_id = tr.user_id
left join post_type_mix ptm on ptm.user_id = tr.user_id
left join null_logic_probe nlp on nlp.user_id = tr.user_id
left join string_flags sf on sf.user_id = tr.user_id
where coalesce(ua.q_count,0) + coalesce(ua.a_count,0) > 0
qualify row_number() over (
    order by fs.composite_score desc nulls last, ua.total_score desc nulls last, tr.reputation desc nulls last, tr.user_id
) <= 200;