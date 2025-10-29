with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
posts_enriched as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.score,
        p.viewcount,
        p.creationdate,
        p.title,
        p.tags,
        p.parentid,
        p.acceptedanswerid,
        p.favoritecount,
        p.answercount,
        p.commentcount,
        p.lastactivitydate,
        case when p.posttypeid = 1 then 1 else 0 end as is_question,
        case when p.posttypeid = 2 then 1 else 0 end as is_answer
    from posts p
    where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_votes,
        count(*) filter (where v.votetypeid in (2,3)) as total_votes,
        max(v.creationdate) as last_vote_at
    from votes v
    where v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
    group by v.postid
),
badges_recent as (
    select
        b.userid,
        count(*) as badges_count,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        max(b.date) as last_badge_at
    from badges b
    where b.date >= (select coalesce(max(date), cast('2024-10-01 12:34:56' as timestamp)) - interval '365 days' from badges)
    group by b.userid
),
comments_agg as (
    select
        c.postid,
        count(*) as comments_count,
        max(c.creationdate) as last_comment_at,
        sum(case when c.score > 0 then 1 else 0 end) as positive_comments
    from comments c
    where c.creationdate >= (select max(creationdate) - interval '365 days' from comments)
    group by c.postid
),
postlinks_dupes as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as related_links
    from postlinks pl
    where pl.creationdate >= (select max(creationdate) - interval '365 days' from postlinks)
    group by pl.postid
),
question_tag as (
    select
        p.id as postid,
        unnest(string_to_array(substring(p.tags, 2, greatest(char_length(p.tags)-2,0)), '><')) as tag
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
),
tag_popularity as (
    select
        qt.tag,
        count(*) as tag_questions_last_year
    from question_tag qt
    join posts_enriched pe on pe.id = qt.postid and pe.is_question = 1
    group by qt.tag
),
accepted_answers_cte as (
    select
        q.id as question_id,
        q.acceptedanswerid,
        a.owneruserid as aa_owner,
        a.score as aa_score,
        a.creationdate as aa_created_at
    from posts q
    left join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
),
user_activity as (
    select
        u.id as userid,
        count(*) filter (where pe.is_question = 1) as questions_count,
        count(*) filter (where pe.is_answer = 1) as answers_count,
        sum(pe.score) as total_post_score,
        avg(nullif(pe.score,0)) as avg_nonzero_post_score,
        max(pe.creationdate) as last_post_at
    from recent_users u
    left join posts_enriched pe on pe.owneruserid = u.id
    group by u.id
),
global_score_stats as (
    select
        percentile_disc(0.9) within group (order by score) as p90_score_global
    from posts_enriched
),
ranked_posts as (
    select
        pe.id,
        pe.posttypeid,
        pe.owneruserid,
        pe.score,
        pe.viewcount,
        pe.creationdate,
        pe.title,
        pe.tags,
        pe.parentid,
        pe.acceptedanswerid,
        pe.favoritecount,
        pe.answercount,
        pe.commentcount,
        pe.lastactivitydate,
        pe.is_question,
        pe.is_answer,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.total_votes,0) as total_votes,
        coalesce(ca.comments_count,0) as comments_count,
        coalesce(pl.duplicate_links,0) as duplicate_links,
        coalesce(pl.related_links,0) as related_links,
        coalesce(va.favorites_votes,0) + coalesce(pe.favoritecount,0) as favorites_total,
        greatest(coalesce(va.last_vote_at, pe.creationdate), coalesce(ca.last_comment_at, pe.creationdate)) as last_engagement_at,
        row_number() over (partition by pe.owneruserid order by pe.score desc, pe.viewcount desc) as rn_by_author,
        gs.p90_score_global
    from posts_enriched pe
    left join votes_agg va on va.postid = pe.id
    left join comments_agg ca on ca.postid = pe.id
    left join postlinks_dupes pl on pl.postid = pe.id
    cross join global_score_stats gs
),
quality_flags as (
    select
        rp.id as postid,
        (rp.is_question = 1 and rp.score >= rp.p90_score_global) as top_decile_question,
        (rp.is_answer = 1 and rp.score >= rp.p90_score_global) as top_decile_answer,
        (rp.downvotes > rp.upvotes) as controversial,
        (rp.duplicate_links > 0 or lower(rp.title) like '%duplicate%') as suspected_duplicate,
        (rp.comments_count >= 10 and rp.total_votes >= 10) as highly_discussed,
        (coalesce(rp.viewcount,0) > 0 and CAST(rp.score AS numeric) / nullif(rp.viewcount,0) > 0.05) as high_score_per_view
    from ranked_posts rp
    group by rp.id, rp.is_question, rp.score, rp.p90_score_global, rp.is_answer, rp.downvotes, rp.upvotes, rp.duplicate_links, rp.title, rp.comments_count, rp.total_votes, rp.viewcount
),
owner_stats as (
    select
        u.id as userid,
        u.displayname,
        u.reputation,
        u.cohort_month,
        ua.questions_count,
        ua.answers_count,
        ua.total_post_score,
        ua.avg_nonzero_post_score,
        br.badges_count,
        br.gold_badges,
        br.silver_badges,
        br.bronze_badges,
        br.last_badge_at,
        u.websiteurl_norm,
        u.location,
        ua.last_post_at
    from recent_users u
    left join user_activity ua on ua.userid = u.id
    left join badges_recent br on br.userid = u.id
),
question_focus as (
    select
        rp.id as postid,
        rp.owneruserid as userid,
        rp.title,
        rp.tags,
        rp.score,
        rp.viewcount,
        rp.favorites_total,
        rp.comments_count,
        rp.last_engagement_at,
        qf.top_decile_question,
        qf.controversial,
        qf.suspected_duplicate,
        qf.highly_discussed,
        qf.high_score_per_view,
        aa.acceptedanswerid,
        aa.aa_owner,
        aa.aa_score,
        aa.aa_created_at,
        rp.rn_by_author
    from ranked_posts rp
    join quality_flags qf on qf.postid = rp.id
    left join accepted_answers_cte aa on aa.question_id = rp.id
    where rp.is_question = 1 and rp.rn_by_author <= 5
),
top_tags as (
    select
        qf.postid,
        t.tag,
        tp.tag_questions_last_year,
        dense_rank() over (partition by qf.postid order by tp.tag_questions_last_year desc, t.tag) as tag_rank
    from question_focus qf
    left join question_tag t on t.postid = qf.postid
    left join tag_popularity tp on tp.tag = t.tag
),
tag_rollup as (
    select
        postid,
        string_agg(tag || ':' || coalesce(CAST(tp.tag_questions_last_year AS varchar),'0'), ', ' order by tag_rank) as tag_stats
    from top_tags tp
    where tag_rank <= 5
    group by postid
),
activity_windows as (
    select
        rp.owneruserid as userid,
        rp.id as postid,
        rp.creationdate,
        sum(rp.score) over (partition by rp.owneruserid order by rp.creationdate rows between unbounded preceding and current row) as running_score_by_user,
        count(*) over (partition by rp.owneruserid order by rp.creationdate rows between unbounded preceding and current row) as running_posts_by_user,
        avg(rp.score) over (partition by rp.owneruserid order by rp.creationdate rows between 10 preceding and current row) as moving_avg_score_11,
        lead(rp.score) over (partition by rp.owneruserid order by rp.creationdate) as next_post_score,
        lag(rp.score) over (partition by rp.owneruserid order by rp.creationdate) as prev_post_score
    from ranked_posts rp
)
select
    qs.postid,
    coalesce(os.displayname, '(deleted user)') as author,
    os.reputation,
    os.cohort_month,
    os.badges_count,
    os.gold_badges,
    os.silver_badges,
    os.bronze_badges,
    coalesce(os.questions_count,0) as author_questions_last_year,
    coalesce(os.answers_count,0) as author_answers_last_year,
    os.total_post_score as author_total_score_last_year,
    round(coalesce(os.avg_nonzero_post_score,0), 2) as author_avg_nonzero_post_score,
    qs.title,
    coalesce(qs.tags, '[]') as tags_raw,
    tr.tag_stats as top_tag_stats,
    qs.score,
    qs.viewcount,
    qs.favorites_total,
    qs.comments_count,
    qs.last_engagement_at,
    qs.top_decile_question,
    qs.controversial,
    qs.suspected_duplicate,
    qs.highly_discussed,
    qs.high_score_per_view,
    case when qs.acceptedanswerid is not null then 'Yes' else 'No' end as has_accepted_answer,
    qs.aa_owner as accepted_answer_ownerid,
    qs.aa_score as accepted_answer_score,
    CAST(floor(extract(epoch from age(cast('2024-10-01 12:34:56' as timestamp), qs.aa_created_at))) AS bigint) as accepted_answer_age_sec,
    aw.running_score_by_user,
    aw.running_posts_by_user,
    round(coalesce(aw.moving_avg_score_11,0), 2) as moving_avg_score_last_11,
    aw.prev_post_score,
    aw.next_post_score,
    case
        when qs.score >= 10
         and coalesce(qs.viewcount,0) > 100
         and (qs.highly_discussed or qs.high_score_per_view)
         and not qs.suspected_duplicate
         and (os.badges_count is null or os.badges_count >= 3)
        then 'HIGHLIGHT'
        when qs.score <= 0
         and (qs.controversial or qs.suspected_duplicate)
        then 'REVIEW'
        else 'NORMAL'
    end as review_bucket
from question_focus qs
left join owner_stats os on os.userid = qs.userid
left join tag_rollup tr on tr.postid = qs.postid
left join activity_windows aw on aw.postid = qs.postid
where (
    (os.websiteurl_norm ilike '%github%' or os.websiteurl_norm = 'N/A')
    and coalesce(os.location, '') not ilike '%recruiter%'
    and (
        (
            lower(qs.title) like '%performance%'
            or lower(qs.title) like '%optimiz%'
            or lower(qs.title) like '%index%'
        )
        or qs.tags ilike '%<sql>%'
        or (select count(*) from comments c where c.postid = qs.postid and c.text ilike '%benchmark%') > 0
    )
)
union all
select
    rp.id as postid,
    coalesce(u.displayname, '(deleted user)') as author,
    u.reputation,
    date_trunc('month', coalesce(u.creationdate, rp.creationdate)) as cohort_month,
    coalesce(br.badges_count,0) as badges_count,
    coalesce(br.gold_badges,0) as gold_badges,
    coalesce(br.silver_badges,0) as silver_badges,
    coalesce(br.bronze_badges,0) as bronze_badges,
    null as author_questions_last_year,
    null as author_answers_last_year,
    null as author_total_score_last_year,
    null as author_avg_nonzero_post_score,
    rp.title,
    coalesce(rp.tags, '[]') as tags_raw,
    null as top_tag_stats,
    rp.score,
    rp.viewcount,
    coalesce(va.favorites_votes,0) + coalesce(rp.favoritecount,0) as favorites_total,
    coalesce(ca.comments_count,0) as comments_count,
    greatest(coalesce(va.last_vote_at, rp.creationdate), coalesce(ca.last_comment_at, rp.creationdate)) as last_engagement_at,
    false as top_decile_question,
    (coalesce(va.downvotes,0) > coalesce(va.upvotes,0)) as controversial,
    coalesce(pl.duplicate_links,0) > 0 as suspected_duplicate,
    coalesce(ca.comments_count,0) >= 20 as highly_discussed,
    (coalesce(rp.viewcount,0) > 0 and CAST(rp.score AS numeric) / nullif(rp.viewcount,0) > 0.1) as high_score_per_view,
    case when rp.acceptedanswerid is not null then 'Yes' else 'No' end as has_accepted_answer,
    null as accepted_answer_ownerid,
    null as accepted_answer_score,
    null as accepted_answer_age_sec,
    null as running_score_by_user,
    null as running_posts_by_user,
    null as moving_avg_score_last_11,
    null as prev_post_score,
    null as next_post_score,
    'FALLBACK' as review_bucket
from ranked_posts rp
left join users u on u.id = rp.owneruserid
left join votes_agg va on va.postid = rp.id
left join comments_agg ca on ca.postid = rp.id
left join postlinks_dupes pl on pl.postid = rp.id
left join badges_recent br on br.userid = u.id
where rp.is_question = 1
  and rp.rn_by_author = 1
  and rp.score between -2 and 2
order by review_bucket desc, score desc, viewcount desc, postid asc
limit 500;