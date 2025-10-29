-- {"query": "445.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3494} 
with params as (
    select 
        50::int as min_rep,
        2015::int as start_year,
        2020::int as end_year
),
-- Active users with reputation and basic activity windowed stats
active_users as (
    select 
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as website_norm,
        dense_rank() over (order by u.reputation desc, u.id) as rep_rank
    from users u
    join params p on u.reputation >= p.min_rep
),
-- Questions and answers in year range with derived fields
year_posts as (
    select 
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        date_part('year', p.creationdate)::int as yr,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.tags,
        p.title,
        p.parentid,
        p.acceptedanswerid,
        case when p.tags is not null 
             then array_length(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'), 1)
             else 0 end as tag_cnt
    from posts p
    join params pr on date_part('year', p.creationdate) between pr.start_year and pr.end_year
),
-- Normalize tags into rows
question_tags as (
    select 
        q.id as question_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tagname
    from year_posts q
    where q.posttypeid = 1
),
-- Per-user yearly aggregates for questions and answers
user_year_stats as (
    select
        a.user_id,
        yp.yr,
        count(*) filter (where yp.posttypeid = 1) as q_cnt,
        count(*) filter (where yp.posttypeid = 2) as a_cnt,
        sum(yp.score) as total_score,
        avg(nullif(yp.score,0)) as avg_nonzero_score,
        sum(coalesce(yp.viewcount,0)) as total_views,
        avg(coalesce(yp.commentcount,0)) as avg_comments,
        sum(case when yp.posttypeid = 1 and yp.acceptedanswerid is not null then 1 else 0 end) as questions_with_accepted,
        sum(case when yp.posttypeid = 2 and exists (
            select 1 
            from posts q 
            where q.id = yp.parentid and q.acceptedanswerid = yp.id
        ) then 1 else 0 end) as answers_accepted
    from active_users a
    left join year_posts yp on yp.owneruserid = a.user_id
    group by a.user_id, yp.yr
),
-- Recent comment activity with sentiment-ish proxy and string work
recent_comments as (
    select 
        c.userid as user_id,
        date_part('year', c.creationdate)::int as yr,
        count(*) as comment_cnt,
        sum(c.score) as comment_score,
        avg(length(c.text)) as avg_comment_len,
        sum(case when position('thanks' in lower(c.text))>0 or position('great' in lower(c.text))>0 then 1 else 0 end) as pos_words,
        sum(case when position('worst' in lower(c.text))>0 or position('bad' in lower(c.text))>0 then 1 else 0 end) as neg_words
    from comments c
    join params pr on date_part('year', c.creationdate) between pr.start_year and pr.end_year
    group by c.userid, date_part('year', c.creationdate)
),
-- Votes cast per user-year with window distributions
user_votes as (
    select 
        v.userid as user_id,
        date_part('year', v.creationdate)::int as yr,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 1) as accepts_cast,
        sum(coalesce(v.bountyamount,0)) as bounty_spent
    from votes v
    join params pr on date_part('year', v.creationdate) between pr.start_year and pr.end_year
    group by v.userid, date_part('year', v.creationdate)
),
-- Duplicate closures via PostHistory and PostLinks
dup_closures as (
    select
        ph.postid as question_id,
        date_part('year', ph.creationdate)::int as yr,
        count(*) filter (where ph.posthistorytypeid = 10 and ph.comment::int in (1,101)) as dup_close_events
    from posthistory ph
    join params pr on date_part('year', ph.creationdate) between pr.start_year and pr.end_year
    group by ph.postid, date_part('year', ph.creationdate)
),
-- Link graph metrics: duplicates and linked counts per question
link_graph as (
    select
        pl.postid as question_id,
        date_part('year', pl.creationdate)::int as yr,
        count(*) filter (where pl.linktypeid = 3) as dup_links,
        count(*) filter (where pl.linktypeid = 1) as related_links
    from postlinks pl
    join params pr on date_part('year', pl.creationdate) between pr.start_year and pr.end_year
    group by pl.postid, date_part('year', pl.creationdate)
),
-- Badge acquisitions per class per user-year
badge_stats as (
    select
        b.userid as user_id,
        date_part('year', b.date)::int as yr,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges
    from badges b
    join params pr on date_part('year', b.date) between pr.start_year and pr.end_year
    group by b.userid, date_part('year', b.date)
),
-- Per-user-year tag concentration: top tag share
user_tag_share as (
    select 
        qt.tagname,
        p.owneruserid as user_id,
        p.yr,
        count(*) as tag_posts,
        sum(count(*)) over (partition by p.owneruserid, p.yr) as total_posts_year,
        row_number() over (partition by p.owneruserid, p.yr order by count(*) desc, qt.tagname) as rn
    from question_tags qt
    join year_posts p on p.id = qt.question_id
    group by qt.tagname, p.owneruserid, p.yr
),
user_tag_top as (
    select 
        user_id,
        yr,
        case when total_posts_year > 0 then tag_posts::numeric / total_posts_year else null end as top_tag_share,
        tagname as top_tag
    from user_tag_share
    where rn = 1
),
-- Windowed ranks and deltas across years
user_year_enriched as (
    select 
        a.user_id,
        a.displayname,
        a.reputation,
        a.creationdate,
        a.location,
        a.website_norm,
        a.rep_rank,
        ys.yr,
        coalesce(ys.q_cnt,0) as q_cnt,
        coalesce(ys.a_cnt,0) as a_cnt,
        coalesce(ys.total_score,0) as total_score,
        ys.avg_nonzero_score,
        coalesce(ys.total_views,0) as total_views,
        coalesce(ys.avg_comments,0) as avg_comments,
        coalesce(ys.questions_with_accepted,0) as questions_with_accepted,
        coalesce(ys.answers_accepted,0) as answers_accepted,
        coalesce(rc.comment_cnt,0) as comment_cnt,
        coalesce(rc.comment_score,0) as comment_score,
        rc.avg_comment_len,
        coalesce(rc.pos_words,0) as pos_words,
        coalesce(rc.neg_words,0) as neg_words,
        coalesce(uv.upvotes_cast,0) as upvotes_cast,
        coalesce(uv.downvotes_cast,0) as downvotes_cast,
        coalesce(uv.accepts_cast,0) as accepts_cast,
        coalesce(uv.bounty_spent,0) as bounty_spent,
        coalesce(dc.dup_close_events,0) as dup_close_events,
        coalesce(lg.dup_links,0) as dup_links,
        coalesce(lg.related_links,0) as related_links,
        utt.top_tag,
        utt.top_tag_share,
        sum(coalesce(ys.q_cnt,0) + coalesce(ys.a_cnt,0)) over (partition by a.user_id order by ys.yr rows between unbounded preceding and current row) as cum_posts,
        lag(ys.total_score) over (partition by a.user_id order by ys.yr) as prev_total_score,
        lead(ys.total_score) over (partition by a.user_id order by ys.yr) as next_total_score
    from active_users a
    left join user_year_stats ys on ys.user_id = a.user_id
    left join recent_comments rc on rc.user_id = a.user_id and rc.yr = ys.yr
    left join user_votes uv on uv.user_id = a.user_id and uv.yr = ys.yr
    left join dup_closures dc on dc.question_id in (
        select id from posts where owneruserid = a.user_id and posttypeid = 1
    ) and dc.yr = ys.yr
    left join link_graph lg on lg.question_id in (
        select id from posts where owneruserid = a.user_id and posttypeid = 1
    ) and lg.yr = ys.yr
    left join user_tag_top utt on utt.user_id = a.user_id and utt.yr = ys.yr
),
-- Classify user-year activity levels with complex predicates
user_year_class as (
    select 
        u.*,
        case 
            when coalesce(u.a_cnt,0) >= 10 and coalesce(u.q_cnt,0) >= 5 and coalesce(u.total_score,0) >= 50 then 'Power'
            when coalesce(u.a_cnt,0) >= 5 or coalesce(u.q_cnt,0) >= 3 then 'Active'
            when coalesce(u.a_cnt,0) + coalesce(u.q_cnt,0) = 0 then 'Dormant'
            else 'Casual'
        end as activity_class,
        case 
            when coalesce(u.downvotes_cast,0) > coalesce(u.upvotes_cast,0) then 'Critical'
            when coalesce(u.upvotes_cast,0) >= 5 and coalesce(u.downvotes_cast,0) = 0 then 'Positive'
            else 'Mixed'
        end as voting_mood,
        case 
            when coalesce(u.top_tag_share,0) >= 0.5 then 'Specialist'
            when u.top_tag is null then 'None'
            else 'Generalist'
        end as tag_focus
    from user_year_enriched u
),
-- Rank within year by composite score with NULL-safe arithmetic
ranked as (
    select 
        uyc.*,
        (
            coalesce(uyc.total_score,0) 
            + coalesce(uyc.answers_accepted,0) * 5
            + coalesce(uyc.questions_with_accepted,0) * 2
            + (case when uyc.avg_nonzero_score is null then 0 else uyc.avg_nonzero_score end)
            + least(coalesce(uyc.bounty_spent,0)/50.0, 20)
            - greatest(coalesce(uyc.downvotes_cast,0) - coalesce(uyc.upvotes_cast,0), 0)
        ) as composite_score,
        row_number() over (
            partition by uyc.yr 
            order by 
                coalesce(uyc.total_score,0) 
                + coalesce(uyc.answers_accepted,0) * 5
                + coalesce(uyc.questions_with_accepted,0) * 2
                + (case when uyc.avg_nonzero_score is null then 0 else uyc.avg_nonzero_score end)
                + least(coalesce(uyc.bounty_spent,0)/50.0, 20)
                - greatest(coalesce(uyc.downvotes_cast,0) - coalesce(uyc.upvotes_cast,0), 0)
                desc,
                uyc.user_id
        ) as yr_rank
    from user_year_class uyc
),
-- Pull in a cross-check using set operator: users with any duplicate links vs not
dup_engagement as (
    select user_id, yr, 'HasDupLinks' as flag
    from user_year_enriched
    where dup_links > 0
    union
    select user_id, yr, 'NoDupLinks' as flag
    from user_year_enriched
    where coalesce(dup_links,0) = 0
),
-- Correlated subquery: percentile of composite vs peers in same year
with_percentile as (
    select 
        r.*,
        (
            select percentile_cont(0.5) within group (order by r2.composite_score)
            from ranked r2
            where r2.yr = r.yr
        ) as median_composite,
        (
            select avg(r3.composite_score)
            from ranked r3
            where r3.yr = r.yr
        ) as mean_composite
    from ranked r
)
select 
    wp.yr,
    wp.yr_rank,
    wp.user_id,
    wp.displayname,
    wp.reputation,
    wp.activity_class,
    wp.voting_mood,
    wp.tag_focus,
    wp.top_tag,
    round(coalesce(wp.top_tag_share,0)::numeric, 3) as top_tag_share,
    wp.q_cnt, wp.a_cnt, wp.total_score, wp.answers_accepted, wp.questions_with_accepted,
    wp.total_views, round(coalesce(wp.avg_comments,0)::numeric,2) as avg_comments,
    wp.comment_cnt, wp.comment_score, round(coalesce(wp.avg_comment_len,0)::numeric,1) as avg_comment_len,
    wp.upvotes_cast, wp.downvotes_cast, wp.accepts_cast, wp.bounty_spent,
    wp.dup_close_events, wp.dup_links, wp.related_links,
    round(wp.composite_score::numeric,2) as composite_score,
    round(coalesce(wp.median_composite,0)::numeric,2) as median_composite,
    round(coalesce(wp.mean_composite,0)::numeric,2) as mean_composite,
    -- String expression and NULL logic
    coalesce(wp.location, 'Unknown') as location,
    case 
        when wp.website_norm like 'http%' then wp.website_norm
        when wp.website_norm = 'N/A' then null
        when wp.website_norm is null then null
        else 'http://' || wp.website_norm
    end as website_url_normalized,
    -- Trend indicators
    case when wp.prev_total_score is null then null 
         when wp.total_score > wp.prev_total_score then 'Up' 
         when wp.total_score < wp.prev_total_score then 'Down' 
         else 'Flat' end as score_trend_vs_prev,
    case when wp.next_total_score is null then null 
         when wp.total_score > wp.next_total_score then 'Peak' 
         when wp.total_score < wp.next_total_score then 'Rising' 
         else 'Plateau' end as local_trend,
    -- Outer join-derived flags via exists
    exists (
        select 1 from dup_engagement de 
        where de.user_id = wp.user_id and de.yr = wp.yr and de.flag = 'HasDupLinks'
    ) as engaged_in_dups
from with_percentile wp
where wp.yr_rank <= 50
order by wp.yr, wp.yr_rank, wp.user_id;