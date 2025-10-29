-- {"query": "97.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2379} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as country_guess,
           row_number() over (order by u.creationdate desc, u.id) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        u.user_id,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        count(*) filter (where c.id is not null) as total_comments,
        sum(greatest(p.score, 0)) as nonneg_post_score,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes_received,
        count(*) filter (where v.votetypeid = 5) as favorites_received
    from recent_users u
    left join posts p on p.owneruserid = u.user_id
    left join comments c on c.userid = u.user_id
    left join votes v on v.postid = p.id
    group by u.user_id
),
tag_extract as (
    select
        q.id as question_id,
        lower(trim(x.tag)) as tag
    from posts q
    cross join lateral unnest(string_to_array(substring(coalesce(q.tags,''), 2, greatest(length(coalesce(q.tags,'')) - 2, 0)), '><')) as x(tag)
    where q.posttypeid = 1
),
user_top_tag as (
    select
        p.owneruserid as user_id,
        t.tag,
        count(*) as tag_posts,
        row_number() over (partition by p.owneruserid order by count(*) desc, min(p.creationdate)) as tag_rank
    from posts p
    join tag_extract t on t.question_id = case when p.posttypeid = 1 then p.id else p.parentid end
    where p.posttypeid in (1,2)
    group by p.owneruserid, t.tag
),
badges_agg as (
    select
        b.userid as user_id,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
post_closure as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        count(distinct case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+' then ph.comment end) as distinct_close_reasons
    from posthistory ph
    group by ph.postid
),
answers_metrics as (
    select
        a.parentid as question_id,
        percentile_cont(0.5) within group (order by a.score) as median_answer_score,
        avg(a.score) as avg_answer_score,
        count(*) as answers_count,
        sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as accepted_present
    from posts a
    join posts q on q.id = a.parentid and q.posttypeid = 1
    where a.posttypeid = 2
    group by a.parentid
),
question_hotness as (
    select
        q.id as question_id,
        q.owneruserid as owner_id,
        q.creationdate,
        q.viewcount,
        q.score,
        q.favoritecount,
        coalesce(am.answers_count,0) as answers_count,
        coalesce(am.avg_answer_score,0) as avg_answer_score,
        coalesce(am.median_answer_score,0) as median_answer_score,
        coalesce(pc.close_events,0) as close_events,
        coalesce(pc.reopen_events,0) as reopen_events,
        coalesce(pc.distinct_close_reasons,0) as distinct_close_reasons,
        case when q.closeddate is not null then 1 else 0 end as is_closed,
        0.5 * ln(1 + greatest(q.viewcount,0)) +
        1.0 * greatest(q.score,0) +
        0.3 * coalesce(am.answers_count,0) +
        0.2 * coalesce(am.avg_answer_score,0) +
        0.1 * coalesce(am.median_answer_score,0) -
        0.7 * coalesce(pc.close_events,0) +
        0.4 * coalesce(pc.reopen_events,0) +
        0.2 * coalesce(q.favoritecount,0) -
        case when q.closeddate is not null then 2 else 0 end
        as hotness_score
    from posts q
    left join answers_metrics am on am.question_id = q.id
    left join post_closure pc on pc.postid = q.id
    where q.posttypeid = 1
),
dup_links as (
    select
        pl.postid as dup_post_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as linked_links,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
user_rollup as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.country_guess,
        ua.total_posts,
        ua.total_comments,
        ua.nonneg_post_score,
        ua.net_votes_received,
        ua.favorites_received,
        coalesce(ba.gold_badges,0) as gold_badges,
        coalesce(ba.silver_badges,0) as silver_badges,
        coalesce(ba.bronze_badges,0) as bronze_badges,
        ba.last_badge_date,
        tt.tag as top_tag
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join badges_agg ba on ba.user_id = ru.user_id
    left join user_top_tag tt on tt.user_id = ru.user_id and tt.tag_rank = 1
),
question_enriched as (
    select
        qh.question_id,
        qh.owner_id,
        qh.hotness_score,
        qh.viewcount,
        qh.score,
        qh.favoritecount,
        qh.answers_count,
        qh.is_closed,
        coalesce(dl.duplicate_links,0) as duplicate_links,
        coalesce(dl.linked_links,0) as linked_links,
        coalesce(dl.last_link_date, qh.creationdate) as last_link_date
    from question_hotness qh
    left join dup_links dl on dl.dup_post_id = qh.question_id
),
user_question_stats as (
    select
        qe.owner_id as user_id,
        count(*) as questions_count,
        avg(qe.hotness_score) as avg_hotness,
        max(qe.hotness_score) as max_hotness,
        sum(case when qe.is_closed = 1 then 1 else 0 end) as closed_questions,
        sum(qe.duplicate_links) as total_dup_links,
        sum(qe.linked_links) as total_linked_links,
        max(qe.last_link_date) as last_link_date
    from question_enriched qe
    group by qe.owner_id
),
ranked_users as (
    select
        ur.*,
        uqs.questions_count,
        uqs.avg_hotness,
        uqs.max_hotness,
        uqs.closed_questions,
        uqs.total_dup_links,
        uqs.total_linked_links,
        uqs.last_link_date,
        case
            when coalesce(ur.total_posts,0) = 0 then null
            else round( (coalesce(ur.nonneg_post_score,0)::numeric + coalesce(ur.net_votes_received,0)::numeric + coalesce(uqs.avg_hotness,0)) / greatest(ur.total_posts,1), 4)
        end as per_post_perf,
        dense_rank() over (order by
            coalesce(ur.reputation,0) desc,
            coalesce(uqs.avg_hotness,0) desc,
            coalesce(ur.total_posts,0) desc,
            coalesce(ur.total_comments,0) desc
        ) as perf_rank
    from user_rollup ur
    left join user_question_stats uqs on uqs.user_id = ur.user_id
),
qualified as (
    select *
    from ranked_users r
    where coalesce(r.total_posts,0) >= 5
      and coalesce(r.questions_count,0) >= 1
      and (r.gold_badges + r.silver_badges + r.bronze_badges) >= 1
)
select
    q.user_id,
    q.displayname,
    q.reputation,
    q.country_guess,
    q.top_tag,
    q.total_posts,
    q.total_comments,
    q.questions_count,
    q.avg_hotness,
    q.max_hotness,
    q.closed_questions,
    q.total_dup_links,
    q.total_linked_links,
    q.per_post_perf,
    q.perf_rank,
    q.gold_badges,
    q.silver_badges,
    q.bronze_badges,
    q.last_badge_date,
    q.last_link_date,
    case
        when q.country_guess ilike '%united%' then 'EN'
        when q.country_guess ~* '(france|paris)' then 'FR'
        when q.country_guess ~* '(germany|berlin)' then 'DE'
        when q.country_guess = 'Unknown' then null
        else 'OT'
    end as country_code_guess,
    coalesce((
        select string_agg(t.tagname, ',' order by t.count desc)
        from tags t
        where lower(t.tagname) = lower(coalesce(q.top_tag,''))
           or lower(t.tagname) like lower(coalesce(q.top_tag,'')) || '%'
    ), '') as related_tags
from qualified q
where exists (
    select 1
    from posts p
    where p.owneruserid = q.user_id
      and p.posttypeid in (1,2)
      and p.score >= (select avg(score) from posts p2 where p2.posttypeid = p.posttypeid)
)
and not exists (
    select 1
    from comments c
    where c.userid = q.user_id
      and c.text ilike '%spam%' and c.score < 0
)
order by q.perf_rank, q.user_id
limit 200;