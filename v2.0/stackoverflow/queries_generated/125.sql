-- {"query": "125.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3152} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
           date_trunc('month', u.creationdate) as cohort_month,
           row_number() over (order by u.creationdate desc, u.id desc) as rn_global
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        u.id as user_id,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(coalesce(p.score,0)) as post_score_sum,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as question_views,
        max(p.creationdate) as last_post_date,
        min(p.creationdate) as first_post_date
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
user_votes as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 5) as favorites_cast,
        count(*) filter (where v.votetypeid in (8,9)) as bounty_actions,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
    from votes v
    where v.userid is not null
    group by v.userid
),
post_interactions as (
    select
        u.id as user_id,
        count(distinct c.id) as comments_made,
        count(distinct c.postid) as distinct_posts_commented,
        max(c.creationdate) as last_comment_date
    from users u
    left join comments c on c.userid = u.id
    group by u.id
),
badge_summary as (
    select
        b.userid as user_id,
        count(*) as badges_total,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_metrics as (
    select
        q.owneruserid as user_id,
        count(*) as questions_total,
        sum(coalesce(q.answercount,0)) as answers_received,
        count(*) filter (where q.acceptedanswerid is not null) as accepted_questions,
        avg(nullif(q.viewcount,0)) as avg_views_nonzero,
        percentile_disc(0.9) within group (order by coalesce(q.score,0)) as p90_qscore
    from posts q
    where q.posttypeid = 1
    group by q.owneruserid
),
answer_metrics as (
    select
        a.owneruserid as user_id,
        count(*) as answers_total,
        count(*) filter (
            where exists (
                select 1
                from posts q
                where q.id = a.parentid
                  and q.acceptedanswerid = a.id
            )
        ) as accepted_answers,
        avg(coalesce(a.score,0)) as avg_answer_score,
        percentile_disc(0.5) within group (order by coalesce(a.score,0)) as median_answer_score
    from posts a
    where a.posttypeid = 2
    group by a.owneruserid
),
edits_and_closures as (
    select
        ph.userid as user_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edits_count,
        count(*) filter (where ph.posthistorytypeid in (10,35)) as closes_migrations,
        count(*) filter (where ph.posthistorytypeid = 11) as reopens,
        count(*) filter (where ph.posthistorytypeid = 19) as protections
    from posthistory ph
    group by ph.userid
),
linked_duplicates as (
    select
        q.owneruserid as user_id,
        count(*) filter (where pl.linktypeid = 3) as dup_marks_outgoing,
        count(*) filter (where back.linktypeid = 3) as dup_marks_incoming
    from posts q
    left join postlinks pl on pl.postid = q.id and pl.linktypeid = 3
    left join postlinks back on back.relatedpostid = q.id and back.linktypeid = 3
    where q.posttypeid = 1
    group by q.owneruserid
),
tag_pref as (
    select
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
    from posts p
    where p.posttypeid = 1 and p.tags is not null
),
top_tags as (
    select user_id, tagname, cnt, rank() over (partition by user_id order by cnt desc, tagname) as rnk
    from (
        select user_id, tagname, count(*) as cnt
        from tag_pref
        group by user_id, tagname
    ) s
),
user_tag_top3 as (
    select tt.user_id,
           string_agg(tt.tagname || ':' || tt.cnt::text, ', ' order by tt.rnk) as top3_tags
    from top_tags tt
    where tt.rnk <= 3
    group by tt.user_id
),
recent_activity_win as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.posttypeid,
        p.creationdate,
        sum(coalesce(p.score,0)) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as cum_score,
        row_number() over (partition by p.owneruserid order by p.creationdate desc, p.id desc) as rn_recent
    from posts p
    where p.owneruserid is not null
),
user_nullness as (
    select
        u.id as user_id,
        case when u.displayname is null or trim(u.displayname) = '' then 1 else 0 end as missing_displayname,
        case when u.location is null then 1 else 0 end as missing_location,
        case when u.websiteurl is null or trim(u.websiteurl) = '' or u.websiteurl !~* '^https?://' then 1 else 0 end as bad_website
    from users u
),
cohort_stats as (
    select
        ru.cohort_month,
        count(*) as users_in_cohort,
        percentile_disc(0.5) within group (order by ua.total_posts) as median_posts,
        avg(ua.total_posts) as avg_posts
    from recent_users ru
    join user_activity ua on ua.user_id = ru.user_id
    group by ru.cohort_month
),
dim_vote_types as (
    select vt.id, vt.name from votetypes vt
),
user_vote_mix as (
    select
        v.userid as user_id,
        vt.name as vote_name,
        count(*) as vote_cnt
    from votes v
    join dim_vote_types vt on vt.id = v.votetypeid
    where v.userid is not null
    group by v.userid, vt.name
),
vote_mix_pivot as (
    select user_id,
           max(case when vote_name = 'UpMod' then vote_cnt end) as upmod_cnt,
           max(case when vote_name = 'DownMod' then vote_cnt end) as downmod_cnt,
           max(case when vote_name = 'Favorite' then vote_cnt end) as favorite_cnt
    from user_vote_mix
    group by user_id
),
question_closure_reasons as (
    select
        q.owneruserid as user_id,
        count(*) filter (where ph.posthistorytypeid in (10,35)) as closed_events,
        count(*) filter (
            where ph.posthistorytypeid in (10,35)
              and (ph.comment ~ '^[0-9]+' or ph.comment is null)
        ) as closures_with_reason_token
    from posts q
    left join posthistory ph on ph.postid = q.id
    where q.posttypeid = 1
    group by q.owneruserid
),
recent_comment_words as (
    select
        c.userid as user_id,
        sum(length(regexp_replace(coalesce(c.text,''), '\s+', ' ', 'g')) - length(replace(regexp_replace(coalesce(c.text,''), '\s+', ' ', 'g'), ' ', '')) + 1) as approx_words
    from comments c
    where c.creationdate >= (select max(creationdate) - interval '90 days' from comments)
      and c.userid is not null
    group by c.userid
),
activity_rank as (
    select
        ru.user_id,
        dense_rank() over (order by coalesce(ua.total_posts,0) desc, coalesce(ba.badges_total,0) desc, ru.reputation desc) as activity_rank_overall
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join badge_summary ba on ba.user_id = ru.user_id
)
select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location,
    ru.websiteurl_norm,
    ru.cohort_month,
    ua.total_posts,
    ua.questions,
    ua.answers,
    ua.post_score_sum,
    ua.question_views,
    ua.first_post_date,
    ua.last_post_date,
    um.top3_tags,
    qm.questions_total,
    qm.answers_received,
    qm.accepted_questions,
    am.answers_total,
    am.accepted_answers,
    am.avg_answer_score,
    am.median_answer_score,
    ea.edits_count,
    ea.closes_migrations,
    ea.reopens,
    ea.protections,
    ld.dup_marks_outgoing,
    ld.dup_marks_incoming,
    bs.badges_total,
    bs.gold_badges,
    bs.silver_badges,
    bs.bronze_badges,
    bs.tag_badges,
    bs.last_badge_date,
    vi.upmod_cnt,
    vi.downmod_cnt,
    vi.favorite_cnt,
    qcr.closed_events,
    qcr.closures_with_reason_token,
    pi.comments_made,
    pi.distinct_posts_commented,
    pi.last_comment_date,
    rcw.approx_words,
    ra.activity_rank_overall,
    -- complex derived metrics
    case
        when coalesce(ua.total_posts,0) = 0 then null
        else round(coalesce(am.answers_total,0)::numeric / nullif(ua.total_posts,0), 3)
    end as answer_share,
    case
        when coalesce(qm.questions_total,0) = 0 then 0
        else round(qm.accepted_questions::numeric / nullif(qm.questions_total,0), 3)
    end as question_accept_rate,
    round(coalesce(am.accepted_answers,0)::numeric / nullif(am.answers_total,0), 3) as answer_accept_rate,
    round(coalesce(vi.upmod_cnt,0)::numeric / nullif(coalesce(vi.downmod_cnt,0) + coalesce(vi.upmod_cnt,0),0), 3) as upvote_ratio_cast,
    case
        when coalesce(qm.avg_views_nonzero,0) > 1000 then 'high'
        when coalesce(qm.avg_views_nonzero,0) > 100 then 'medium'
        when qm.avg_views_nonzero is null then 'n/a'
        else 'low'
    end as avg_question_views_bucket,
    case when un.missing_displayname = 1 or un.bad_website = 1 then 1 else 0 end as profile_quality_flag,
    coalesce(rw.cum_score, 0) as recent_cum_score,
    (select count(*) from posts p2 where p2.owneruserid = ru.user_id and p2.creationdate >= now() - interval '30 days') as posts_last_30d,
    (select count(*) from comments c2 where c2.userid = ru.user_id and c2.creationdate >= now() - interval '30 days') as comments_last_30d,
    -- null/empty handling showcase
    coalesce(nullif(trim(ru.displayname), ''), '(anonymous)') as displayname_norm
from recent_users ru
left join user_activity ua on ua.user_id = ru.user_id
left join user_tag_top3 um on um.user_id = ru.user_id
left join question_metrics qm on qm.user_id = ru.user_id
left join answer_metrics am on am.user_id = ru.user_id
left join edits_and_closures ea on ea.user_id = ru.user_id
left join linked_duplicates ld on ld.user_id = ru.user_id
left join badge_summary bs on bs.user_id = ru.user_id
left join vote_mix_pivot vi on vi.user_id = ru.user_id
left join question_closure_reasons qcr on qcr.user_id = ru.user_id
left join post_interactions pi on pi.user_id = ru.user_id
left join recent_comment_words rcw on rcw.user_id = ru.user_id
left join user_nullness un on un.user_id = ru.user_id
left join recent_activity_win rw on rw.user_id = ru.user_id and rw.rn_recent = 1
left join activity_rank ra on ra.user_id = ru.user_id
where
    (
        coalesce(ua.total_posts,0) > 0
        or coalesce(bs.badges_total,0) > 0
        or coalesce(pi.comments_made,0) > 0
    )
    and (
        ru.reputation >= (
            select percentile_disc(0.75) within group (order by reputation)
            from users
        )
        or coalesce(am.answers_total,0) >= 10
        or coalesce(qm.questions_total,0) >= 5
    )
order by
    ra.activity_rank_overall nulls last,
    coalesce(ua.total_posts,0) desc,
    ru.reputation desc
limit 500;