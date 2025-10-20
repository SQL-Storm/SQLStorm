-- {"query": "8059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2803} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        dense_rank() over (order by u.creationdate desc) as recency_rank
    from users u
),
top_recent_users as (
    select *
    from recent_users
    where recency_rank <= 500
),
user_badge_agg as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
user_post_stats as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as question_count,
        count(*) filter (where p.posttypeid = 2) as answer_count,
        sum(coalesce(p.score, 0)) as total_post_score,
        sum(coalesce(p.viewcount, 0)) as total_views,
        max(p.creationdate) as last_post_date,
        sum(case when p.posttypeid = 1 and p.acceptedanswerid is not null then 1 else 0 end) as accepted_questions,
        avg(nullif(p.commentcount, 0)) as avg_nonzero_commentcount
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
question_tag_counts as (
    select
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2, 0)), '><')) as tagname
    from posts p
    where p.posttypeid = 1
      and p.owneruserid is not null
      and p.tags is not null
),
user_top_tag as (
    select
        q.user_id,
        (array_agg(tagname order by cnt desc, tagname asc))[1] as top_tag,
        max(cnt) as top_tag_count
    from (
        select user_id, tagname, count(*) as cnt
        from question_tag_counts
        group by user_id, tagname
    ) s
    group by q.user_id
),
answer_accepts as (
    select
        a.owneruserid as user_id,
        count(*) as answers_accepted
    from posts q
    join posts a
      on a.id = q.acceptedanswerid
    where q.posttypeid = 1
      and a.posttypeid = 2
      and a.owneruserid is not null
    group by a.owneruserid
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
    from votes v
    group by v.postid
),
user_vote_agg as (
    select
        p.owneruserid as user_id,
        sum(coalesce(va.upvotes,0)) as recv_upvotes,
        sum(coalesce(va.downvotes,0)) as recv_downvotes,
        sum(coalesce(va.favorites,0)) as recv_favorites
    from posts p
    left join vote_agg va on va.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
post_close_info as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_raw
    from posthistory ph
    group by ph.postid
),
user_close_stats as (
    select
        p.owneruserid as user_id,
        count(*) filter (where pci.first_close_date is not null) as closed_posts,
        sum(coalesce(pci.close_events,0)) as total_close_events,
        sum(coalesce(pci.reopen_events,0)) as total_reopen_events
    from posts p
    left join post_close_info pci on pci.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
linked_duplicates as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id
    from postlinks pl
    where pl.linktypeid = 3
),
user_dup_stats as (
    select
        p.owneruserid as user_id,
        count(*) filter (where ld.dup_post_id is not null) as dup_marked_posts
    from posts p
    left join linked_duplicates ld on ld.dup_post_id = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
user_comment_sentiment as (
    select
        c.userid as user_id,
        avg(case
                when c.text ~* '(?:\b(thanks|great|nice|helpful|good job|awesome)\b)' then 1
                when c.text ~* '(?:\b(bad|terrible|useless|wtf|stupid)\b)' then -1
                else 0
            end
        ) as avg_sentiment,
        count(*) as comment_count
    from comments c
    where c.userid is not null
    group by c.userid
),
user_activity_windows as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.creationdate,
        sum(1) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as cumulative_posts,
        avg(coalesce(p.score,0)) over (partition by p.owneruserid order by p.creationdate rows between 10 preceding and current row) as moving_avg_score_11
    from posts p
    where p.owneruserid is not null
),
user_activity_summary as (
    select
        user_id,
        max(cumulative_posts) as total_posts_windowed,
        max(moving_avg_score_11) as peak_moving_avg_score_11
    from user_activity_windows
    group by user_id
),
ranked_users as (
    select
        tru.user_id,
        tru.displayname,
        tru.reputation,
        tru.creationdate,
        tru.location,
        tru.websiteurl,
        coalesce(ups.question_count,0) as question_count,
        coalesce(ups.answer_count,0) as answer_count,
        coalesce(ups.total_post_score,0) as total_post_score,
        coalesce(ups.total_views,0) as total_views,
        ups.last_post_date,
        coalesce(ups.accepted_questions,0) as accepted_questions,
        ups.avg_nonzero_commentcount,
        coalesce(ua.answers_accepted,0) as answers_accepted,
        coalesce(uva.recv_upvotes,0) as recv_upvotes,
        coalesce(uva.recv_downvotes,0) as recv_downvotes,
        coalesce(uva.recv_favorites,0) as recv_favorites,
        coalesce(uba.total_badges,0) as total_badges,
        coalesce(uba.gold_badges,0) as gold_badges,
        coalesce(uba.silver_badges,0) as silver_badges,
        coalesce(uba.bronze_badges,0) as bronze_badges,
        uba.first_badge_date,
        uba.last_badge_date,
        utt.top_tag,
        utt.top_tag_count,
        ucs.closed_posts,
        ucs.total_close_events,
        ucs.total_reopen_events,
        uds.dup_marked_posts,
        ucs.closed_posts + coalesce(uds.dup_marked_posts,0) as problem_posts,
        ucs.total_reopen_events - coalesce(ucs.total_close_events,0) as reopen_minus_close,
        uas.total_posts_windowed,
        uas.peak_moving_avg_score_11,
        ucs.closed_posts is null as has_no_close_stats
    from top_recent_users tru
    left join user_post_stats ups on ups.user_id = tru.user_id
    left join answer_accepts ua on ua.user_id = tru.user_id
    left join user_vote_agg uva on uva.user_id = tru.user_id
    left join user_badge_agg uba on uba.userid = tru.user_id
    left join user_top_tag utt on utt.user_id = tru.user_id
    left join user_close_stats ucs on ucs.user_id = tru.user_id
    left join user_dup_stats uds on uds.user_id = tru.user_id
    left join user_activity_summary uas on uas.user_id = tru.user_id
),
scored_users as (
    select
        r.*,
        /* Composite score with mixed signals and NULL handling */
        (
            0.35 * coalesce(nullif(r.total_post_score,0), 0) / nullif(r.answer_count + r.question_count, 0)
          + 0.25 * coalesce(r.recv_upvotes - r.recv_downvotes, 0)
          + 0.20 * coalesce(r.answers_accepted, 0)
          + 0.10 * coalesce(r.gold_badges*5 + r.silver_badges*2 + r.bronze_badges, 0)
          - 0.15 * coalesce(r.problem_posts, 0)
          + 0.05 * coalesce(r.peak_moving_avg_score_11, 0)
        ) as composite_score,
        case
            when coalesce(r.total_views,0) > 100000 then 'high'
            when coalesce(r.total_views,0) > 10000 then 'medium'
            when coalesce(r.total_views,0) > 1000 then 'low'
            else 'very low'
        end as visibility_bucket
    from ranked_users r
),
normalized as (
    select
        s.*,
        /* Z-score like normalization using window stats over the candidate set */
        (s.composite_score - avg(s.composite_score) over ()) /
        nullif(stddev_pop(s.composite_score) over (), 0) as z_composite
    from scored_users s
),
final_rank as (
    select
        n.*,
        row_number() over (
            order by
                /* Prioritize high z-score, then fewer problem posts, then newer users */
                n.z_composite desc nulls last,
                n.problem_posts asc nulls last,
                n.creationdate desc
        ) as overall_rank,
        /* tie-breaker hash-like string */
        substring(md5(coalesce(n.displayname,'') || '|' || n.user_id::text || '|' || coalesce(n.location,'')), 1, 12) as tie_key
    from normalized n
)
select
    fr.overall_rank,
    fr.user_id,
    coalesce(nullif(fr.displayname,''), '[user ' || fr.user_id::text || ']') as displayname,
    fr.reputation,
    fr.creationdate,
    coalesce(fr.location, 'Unknown') as location,
    fr.websiteurl,
    fr.question_count,
    fr.answer_count,
    fr.total_post_score,
    fr.total_views,
    fr.recv_upvotes,
    fr.recv_downvotes,
    fr.recv_favorites,
    fr.answers_accepted,
    fr.accepted_questions,
    fr.gold_badges,
    fr.silver_badges,
    fr.bronze_badges,
    fr.top_tag,
    fr.top_tag_count,
    fr.closed_posts,
    fr.total_close_events,
    fr.total_reopen_events,
    fr.dup_marked_posts,
    fr.problem_posts,
    round(fr.composite_score::numeric, 3) as composite_score,
    round(fr.z_composite::numeric, 3) as z_composite,
    fr.visibility_bucket,
    fr.total_posts_windowed,
    round(coalesce(fr.peak_moving_avg_score_11,0)::numeric, 3) as peak_moving_avg_score_11,
    fr.tie_key
from final_rank fr
where (
        fr.answer_count + fr.question_count >= 3
        or fr.total_badges >= 3
     )
  and (
        fr.visibility_bucket in ('medium','high')
        or fr.recv_upvotes - fr.recv_downvotes > 10
     )
  and not fr.has_no_close_stats is null
order by fr.overall_rank
limit 200;