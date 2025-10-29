-- {"query": "989.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3210}
with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as domain,
        date_trunc('month', u.creationdate) as created_month
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score, 0)) as post_score,
        sum(coalesce(p.viewcount, 0)) as views,
        sum(coalesce(p.commentcount, 0)) as comments,
        count(*) filter (where p.closeddate is not null) as closed_posts,
        max(p.lastactivitydate) as last_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
badge_rank as (
    select
        b.userid,
        count(*) as badge_count,
        sum(case when b.class = 1 then 3 when b.class = 2 then 2 when b.class = 3 then 1 else 0 end) as badge_score,
        count(*) filter (where b.tagbased = true) as tag_badges,
        count(*) filter (where b.tagbased = false) as named_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(coalesce(c.score, 0)) as comment_score,
        avg(NULLIF(length(c.text), 0) * 1.0) as avg_comment_len,
        sum(case when c.text ilike '%thanks%' or c.text ilike '%thank you%' then 1 else 0 end) as thanks_comments
    from comments c
    where c.userid is not null
    group by c.userid
),
post_vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        max(v.creationdate) as last_vote
    from votes v
    group by v.postid
),
question_tag_splits as (
    select
        p.id as post_id,
        unnest(string_to_array(substring(coalesce(p.tags,''), 2, greatest(length(coalesce(p.tags,'')) - 2, 0)), '><')) as tag
    from posts p
    where p.posttypeid = 1
),
user_tag_focus as (
    select
        p.owneruserid as user_id,
        q.tag,
        count(*) as tag_posts,
        sum(coalesce(p.score,0)) as tag_score,
        row_number() over (partition by p.owneruserid order by count(*) desc, sum(coalesce(p.score,0)) desc, min(p.creationdate)) as rn
    from posts p
    join question_tag_splits q on q.post_id = p.id
    where p.owneruserid is not null
    group by p.owneruserid, q.tag
),
duplicates as (
    select
        pl.postid as dup_id,
        pl.relatedpostid as original_id,
        min(pl.creationdate) as first_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
closed_reasons as (
    select
        ph.postid,
        min(ph.creationdate) as first_closed_date,
        cast(min(
            case
                when ph.posthistorytypeid = 10 then
                    nullif(trim(regexp_replace(coalesce(ph.comment,''), '[^0-9]', '', 'g')), '')
                else null
            end
        ) as integer) as close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10)
    group by ph.postid
),
user_post_rollup as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(coalesce(pva.upvotes, 0)) as total_upvotes,
        sum(coalesce(pva.downvotes, 0)) as total_downvotes,
        sum(coalesce(pva.favorites, 0)) as total_favorites,
        sum(coalesce(pva.bounty_total, 0)) as total_bounty_earned,
        sum(case when d.dup_id is not null then 1 else 0 end) as dup_marked,
        sum(case when cr.postid is not null then 1 else 0 end) as closed_marked
    from users u
    left join posts p on p.owneruserid = u.id
    left join post_vote_agg pva on pva.postid = p.id
    left join duplicates d on d.dup_id = p.id
    left join closed_reasons cr on cr.postid = p.id
    group by u.id
),
engagement_times as (
    select
        p.owneruserid as user_id,
        avg(extract(epoch from (p.lastactivitydate - p.creationdate))) filter (where p.lastactivitydate is not null and p.creationdate is not null) as avg_lifecycle_seconds,
        percentile_cont(0.5) within group (order by extract(epoch from (p.lastactivitydate - p.creationdate))) filter (where p.lastactivitydate is not null and p.creationdate is not null) as median_lifecycle_seconds,
        max(p.lastactivitydate) as last_seen_post_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
activeness as (
    select
        ru.id as user_id,
        count(*) as active_days,
        sum(posts_per_day) as posts_in_active_days,
        avg(posts_per_day) as avg_posts_per_active_day
    from (
        select
            p.owneruserid as id,
            date_trunc('day', p.creationdate) as d,
            count(*) as posts_per_day
        from posts p
        where p.owneruserid is not null
        group by p.owneruserid, date_trunc('day', p.creationdate)
    ) s
    join recent_users ru on ru.id = s.id
    group by ru.id
),
user_levels as (
    select
        ru.id as user_id,
        case
            when ru.reputation >= 50000 then 'legend'
            when ru.reputation >= 10000 then 'expert'
            when ru.reputation >= 2000 then 'pro'
            when ru.reputation >= 200 then 'regular'
            else 'newbie'
        end as level
    from recent_users ru
),
windowed_rank as (
    select
        ru.id as user_id,
        ru.displayname,
        ru.reputation,
        ru.domain,
        coalesce(ua.post_score,0) + coalesce(upr.total_upvotes,0) - coalesce(upr.total_downvotes,0) as combined_score,
        dense_rank() over (partition by ru.domain order by coalesce(ua.post_score,0) + coalesce(upr.total_upvotes,0) - coalesce(upr.total_downvotes,0) desc) as rank_in_domain
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.id
    left join user_post_rollup upr on upr.user_id = ru.id
),
user_top_tags as (
    select
        utf.user_id,
        string_agg(utf.tag, ', ' order by utf.rn asc) filter (where utf.rn <= 3) as top_3_tags
    from user_tag_focus utf
    group by utf.user_id
),
normalized as (
    select
        ru.id as user_id,
        ru.displayname,
        ru.reputation,
        ru.domain,
        coalesce(ua.q_count,0) as q_count,
        coalesce(ua.a_count,0) as a_count,
        coalesce(ua.post_score,0) as post_score,
        coalesce(ua.views,0) as views,
        coalesce(ua.comments,0) as comments_on_posts,
        coalesce(ua.closed_posts,0) as closed_posts,
        ua.last_activity,
        coalesce(br.badge_count,0) as badge_count,
        coalesce(br.badge_score,0) as badge_score,
        coalesce(br.tag_badges,0) as tag_badges,
        coalesce(br.named_badges,0) as named_badges,
        br.first_badge_date,
        br.last_badge_date,
        coalesce(cs.comment_count,0) as comment_count,
        coalesce(cs.comment_score,0) as comment_score,
        cs.avg_comment_len,
        cs.thanks_comments,
        coalesce(upr.questions,0) as total_questions,
        coalesce(upr.answers,0) as total_answers,
        coalesce(upr.total_upvotes,0) as total_upvotes,
        coalesce(upr.total_downvotes,0) as total_downvotes,
        coalesce(upr.total_favorites,0) as total_favorites,
        coalesce(upr.total_bounty_earned,0) as total_bounty_earned,
        coalesce(upr.dup_marked,0) as duplicate_posts,
        coalesce(upr.closed_marked,0) as closed_posts_marked,
        et.avg_lifecycle_seconds,
        et.median_lifecycle_seconds,
        et.last_seen_post_activity,
        al.active_days,
        al.posts_in_active_days,
        al.avg_posts_per_active_day,
        ul.level,
        wt.rank_in_domain,
        utt.top_3_tags
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.id
    left join badge_rank br on br.userid = ru.id
    left join comment_stats cs on cs.user_id = ru.id
    left join user_post_rollup upr on upr.user_id = ru.id
    left join engagement_times et on et.user_id = ru.id
    left join activeness al on al.user_id = ru.id
    left join user_levels ul on ul.user_id = ru.id
    left join windowed_rank wt on wt.user_id = ru.id
    left join user_top_tags utt on utt.user_id = ru.id
),
domain_peers as (
    select
        n1.user_id,
        n2.user_id as peer_id,
        n2.displayname as peer_name,
        n2.reputation as peer_rep,
        n2.rank_in_domain as peer_rank,
        abs(coalesce(n1.post_score,0) - coalesce(n2.post_score,0)) as score_gap
    from normalized n1
    join normalized n2
      on n1.domain = n2.domain
     and n1.user_id <> n2.user_id
     and n2.rank_in_domain <= 3
),
peer_summary as (
    select
        user_id,
        string_agg(peer_name || ' (rep ' || cast(peer_rep as text) || ', r' || cast(peer_rank as text) || ')', '; ' order by score_gap asc, peer_rank asc) as top_domain_peers
    from domain_peers
    group by user_id
),
score_tiers as (
    select
        n.user_id,
        case
            when coalesce(n.post_score,0) >= 10000 then 'S'
            when coalesce(n.post_score,0) >= 1000 then 'A'
            when coalesce(n.post_score,0) >= 100 then 'B'
            when coalesce(n.post_score,0) >= 10 then 'C'
            else 'D'
        end as score_tier
    from normalized n
),
final_rank as (
    select
        n.*,
        ps.top_domain_peers,
        st.score_tier,
        row_number() over (
            order by
                (coalesce(n.post_score,0) + coalesce(n.total_upvotes,0) - coalesce(n.total_downvotes,0) + coalesce(n.total_bounty_earned,0)) desc,
                coalesce(n.badge_score,0) desc,
                coalesce(n.views,0) desc,
                n.reputation desc
        ) as global_rank
    from normalized n
    left join peer_summary ps on ps.user_id = n.user_id
    left join score_tiers st on st.user_id = n.user_id
)
select
    fr.global_rank,
    fr.user_id,
    fr.displayname,
    fr.level,
    fr.score_tier,
    fr.reputation,
    fr.domain,
    fr.rank_in_domain,
    fr.top_3_tags,
    fr.q_count,
    fr.a_count,
    fr.total_questions,
    fr.total_answers,
    fr.post_score,
    fr.total_upvotes,
    fr.total_downvotes,
    fr.total_favorites,
    fr.total_bounty_earned,
    fr.views,
    fr.comments_on_posts,
    fr.comment_count,
    fr.comment_score,
    fr.avg_comment_len,
    fr.thanks_comments,
    fr.badge_count,
    fr.badge_score,
    fr.tag_badges,
    fr.named_badges,
    fr.duplicate_posts,
    fr.closed_posts,
    fr.closed_posts_marked,
    fr.avg_lifecycle_seconds,
    fr.median_lifecycle_seconds,
    fr.active_days,
    fr.posts_in_active_days,
    fr.avg_posts_per_active_day,
    fr.last_activity,
    fr.last_seen_post_activity,
    fr.first_badge_date,
    fr.last_badge_date,
    coalesce(fr.top_domain_peers, 'none') as top_domain_peers,
    case
        when fr.top_3_tags is null then 'untagged'
        when position('java' in fr.top_3_tags) > 0 then 'java-inclined'
        when position('python' in fr.top_3_tags) > 0 then 'python-inclined'
        when position('javascript' in fr.top_3_tags) > 0 then 'js-inclined'
        else 'generalist'
    end as inferred_specialty
from final_rank fr
where
    coalesce(fr.a_count, 0) + coalesce(fr.q_count, 0) > 0
    and (
        fr.level in ('legend','expert')
        or (fr.score_tier in ('S','A') and fr.rank_in_domain <= 10)
    )
order by fr.global_rank
limit 200;