-- {"query": "847.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2727} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
),
user_badge_agg as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
q_posts as (
    select
        p.id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.favoritecount,
        p.commentcount,
        p.closeddate
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select
        p.id,
        p.parentid,
        p.owneruserid,
        p.creationdate,
        p.score
    from posts p
    where p.posttypeid = 2
),
q_activity as (
    select
        q.owneruserid as user_id,
        count(*) as questions,
        sum(case when q.closeddate is not null then 1 else 0 end) as questions_closed,
        coalesce(sum(q.viewcount), 0) as total_views,
        coalesce(sum(q.score), 0) as total_q_score,
        coalesce(sum(q.answercount), 0) as total_answers_received,
        coalesce(sum(q.favoritecount), 0) as total_favorites,
        coalesce(sum(q.commentcount), 0) as total_q_comments,
        max(q.creationdate) as last_question_date
    from q_posts q
    group by q.owneruserid
),
a_activity as (
    select
        a.owneruserid as user_id,
        count(*) as answers,
        coalesce(sum(a.score), 0) as total_a_score,
        max(a.creationdate) as last_answer_date
    from a_posts a
    group by a.owneruserid
),
q_first_last as (
    select
        owneruserid as user_id,
        min(creationdate) as first_q_date,
        max(creationdate) as last_q_date
    from q_posts
    group by owneruserid
),
a_first_last as (
    select
        owneruserid as user_id,
        min(creationdate) as first_a_date,
        max(creationdate) as last_a_date
    from a_posts
    group by owneruserid
),
dupe_links as (
    select
        pl.postid as duplicate_id,
        pl.relatedpostid as original_id
    from postlinks pl
    where pl.linktypeid = 3
),
dupe_stats as (
    select
        coalesce(q.owneruserid, orig.owneruserid) as user_id,
        count(distinct d.duplicate_id) as dupes_marked,
        count(distinct d.original_id) filter (where orig.id is not null) as originals_linked
    from dupe_links d
    left join q_posts q on q.id = d.duplicate_id
    left join q_posts orig on orig.id = d.original_id
    group by coalesce(q.owneruserid, orig.owneruserid)
),
hot_bumps as (
    select
        ph.postid,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 52) as last_hot_date,
        count(*) filter (where ph.posthistorytypeid = 52) as hot_count,
        count(*) filter (where ph.posthistorytypeid = 50) as community_bumps
    from posthistory ph
    where ph.posthistorytypeid in (50,52)
    group by ph.postid
),
user_hot as (
    select
        p.owneruserid as user_id,
        count(*) filter (where h.last_hot_date is not null) as hot_questions,
        coalesce(sum(h.community_bumps), 0) as total_community_bumps
    from q_posts p
    left join hot_bumps h on h.postid = p.id
    group by p.owneruserid
),
vote_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        count(*) filter (where v.votetypeid = 9) as bounties_closed,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_amount
    from votes v
    group by v.postid
),
user_votes as (
    select
        coalesce(p.owneruserid, p2.owneruserid) as user_id,
        sum(coalesce(va.upvotes,0)) as recv_upvotes,
        sum(coalesce(va.downvotes,0)) as recv_downvotes,
        sum(coalesce(va.bounty_amount,0)) as recv_bounty_amount
    from votes v
    left join posts p on p.id = v.postid and p.posttypeid in (1,2)
    left join posts p2 on p2.id = v.postid and p is null
    left join vote_agg va on va.postid = v.postid
    group by coalesce(p.owneruserid, p2.owneruserid)
),
tag_expansion as (
    select
        q.id as post_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from q_posts q
    where q.tags is not null and length(q.tags) > 2
),
user_top_tag as (
    select user_id, tag, tag_count,
           row_number() over (partition by user_id order by tag_count desc, tag asc) as rn
    from (
        select
            q.owneruserid as user_id,
            t.tag,
            count(*) as tag_count
        from tag_expansion t
        join q_posts q on q.id = t.post_id
        group by q.owneruserid, t.tag
    ) s
),
recent_commenters as (
    select
        c.userid as user_id,
        count(*) as comments_last_year,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
    group by c.userid
),
user_engagement as (
    select
        u.user_id,
        coalesce(qa.questions, 0) as questions,
        coalesce(aa.answers, 0) as answers,
        coalesce(qa.total_views, 0) as total_views,
        coalesce(qa.total_q_score, 0) + coalesce(aa.total_a_score, 0) as net_score,
        coalesce(uv.recv_upvotes, 0) as recv_upvotes,
        coalesce(uv.recv_downvotes, 0) as recv_downvotes,
        coalesce(uv.recv_bounty_amount, 0) as recv_bounty_amount,
        coalesce(qa.total_favorites, 0) as favorites,
        coalesce(qa.total_q_comments, 0) as q_comments,
        coalesce(us.hot_questions, 0) as hot_questions,
        coalesce(us.total_community_bumps, 0) as community_bumps,
        coalesce(ds.dupes_marked, 0) as dupes_marked,
        coalesce(ds.originals_linked, 0) as originals_linked,
        coalesce(rc.comments_last_year, 0) as comments_last_year
    from recent_users u
    left join q_activity qa on qa.user_id = u.user_id
    left join a_activity aa on aa.user_id = u.user_id
    left join user_votes uv on uv.user_id = u.user_id
    left join user_hot us on us.user_id = u.user_id
    left join dupe_stats ds on ds.user_id = u.user_id
    left join recent_commenters rc on rc.user_id = u.user_id
),
durations as (
    select
        u.user_id,
        extract(epoch from (coalesce(a.last_a_date, q.last_q_date, u.creationdate) - coalesce(a.first_a_date, q.first_q_date, u.creationdate))) / 86400.0 as active_days_est,
        extract(epoch from (coalesce(q.last_q_date, u.creationdate) - u.creationdate)) / 86400.0 as days_to_last_question,
        extract(epoch from (coalesce(a.last_a_date, u.creationdate) - u.creationdate)) / 86400.0 as days_to_last_answer
    from recent_users u
    left join q_first_last q on q.user_id = u.user_id
    left join a_first_last a on a.user_id = u.user_id
),
score_percentiles as (
    select
        ue.user_id,
        percentile_cont(0.5) within group (order by ue.net_score) over () as p50_net_score,
        percentile_cont(0.9) within group (order by ue.net_score) over () as p90_net_score
    from user_engagement ue
),
final as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.cohort_month,
        u.location,
        u.websiteurl,
        ba.total_badges,
        ba.gold_badges,
        ba.silver_badges,
        ba.bronze_badges,
        ba.last_badge_date,
        ue.questions,
        ue.answers,
        ue.total_views,
        ue.net_score,
        ue.recv_upvotes,
        ue.recv_downvotes,
        ue.recv_bounty_amount,
        ue.favorites,
        ue.q_comments,
        ue.hot_questions,
        ue.community_bumps,
        ue.dupes_marked,
        ue.originals_linked,
        ue.comments_last_year,
        dt.active_days_est,
        dt.days_to_last_question,
        dt.days_to_last_answer,
        tt.tag as top_tag,
        tt.tag_count as top_tag_count,
        case
            when ue.answers + ue.questions = 0 then null
            else round(ue.net_score::numeric / nullif((ue.answers + ue.questions),0), 3)
        end as avg_score_per_post,
        case
            when ue.recv_upvotes + ue.recv_downvotes = 0 then 0
            else round(ue.recv_upvotes::numeric / nullif((ue.recv_upvotes + ue.recv_downvotes),0), 4)
        end as upvote_ratio,
        case
            when dt.active_days_est is null or dt.active_days_est <= 0 then null
            else round((ue.answers + ue.questions)::numeric / nullif(dt.active_days_est,0), 4)
        end as posts_per_active_day,
        sp.p50_net_score,
        sp.p90_net_score,
        case
            when ue.net_score >= sp.p90_net_score then 'P90+'
            when ue.net_score >= sp.p50_net_score then 'P50-P90'
            else 'Below P50'
        end as net_score_band
    from recent_users u
    left join user_badge_agg ba on ba.userid = u.user_id
    left join user_engagement ue on ue.user_id = u.user_id
    left join durations dt on dt.user_id = u.user_id
    left join score_percentiles sp on sp.user_id = u.user_id
    left join lateral (
        select tag, tag_count
        from user_top_tag utt
        where utt.user_id = u.user_id and utt.rn = 1
    ) tt on true
)
select *
from final
where
    coalesce(answers,0) + coalesce(questions,0) > 0
    and (reputation > 100 or net_score > 0 or hot_questions > 0)
    and (
        top_tag is null
        or top_tag not ilike any (array['%discussion%','%meta%'])
    )
order by
    net_score_band asc,
    avg_score_per_post desc nulls last,
    posts_per_active_day desc nulls last,
    answers desc,
    questions desc,
    total_views desc
limit 500;