with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl_norm,
        dense_rank() over (order by u.creationdate desc) as dr_created
    from users u
),
top_new_users as (
    select *
    from recent_users
    where dr_created <= 1000
),
user_badge_stats as (
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
user_post_activity as (
    select
        p.owneruserid as user_id,
        count(case when p.posttypeid = 1 then 1 end) as question_count,
        count(case when p.posttypeid = 2 then 1 end) as answer_count,
        sum(coalesce(p.score,0)) as total_post_score,
        avg(nullif(p.score,0)) as avg_nonzero_score,
        max(p.lastactivitydate) as last_activity,
        count(case when p.closeddate is not null then 1 end) as closed_posts,
        count(case when p.communityowneddate is not null then 1 end) as community_posts
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
question_tag_expansion as (
    select
        p.id as question_id,
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
),
user_top_tag as (
    select
        q.user_id,
        t.tagname,
        count(*) as tag_uses,
        row_number() over (partition by q.user_id order by count(*) desc, lower(t.tagname)) as rn
    from question_tag_expansion t
    join question_tag_expansion q on q.question_id = t.question_id
    join posts p on p.id = t.question_id
    group by q.user_id, t.tagname
),
user_votes as (
    select
        v.userid as user_id,
        count(case when v.votetypeid = 2 then 1 end) as upvotes_cast,
        count(case when v.votetypeid = 3 then 1 end) as downvotes_cast,
        count(case when v.votetypeid = 5 then 1 end) as favorites_cast,
        count(case when v.votetypeid in (8,9) then 1 end) as bounties_interactions,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    where v.userid is not null
    group by v.userid
),
accepted_answers as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_answers_count
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
      and a.posttypeid = 2
      and a.owneruserid is not null
    group by a.owneruserid
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        sum(coalesce(c.score,0)) as comment_score_total,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
post_link_metrics as (
    select
        p.owneruserid as user_id,
        count(case when pl.linktypeid = 1 then 1 end) as links_linked,
        count(case when pl.linktypeid = 3 then 1 end) as links_duplicate
    from posts p
    left join postlinks pl on pl.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
close_events as (
    select
        ph.postid,
        ph.userid as closer_userid,
        max(ph.creationdate) as last_close_date,
        max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as had_close
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid, ph.userid
),
user_close_influence as (
    select
        p.owneruserid as user_id,
        count(case when ce.had_close = 1 then 1 end) as times_posts_closed,
        max(ce.last_close_date) as last_closed_date
    from posts p
    left join close_events ce on ce.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
user_quality_score as (
    select
        u.user_id,
        (
          coalesce(upa.answer_count,0) * 2
          + coalesce(aa.accepted_answers_count,0) * 5
          + coalesce(upa.total_post_score,0)
        )
        -
        (
          coalesce(upa.closed_posts,0) * 3
          + greatest(coalesce(uv.downvotes_cast,0) - coalesce(uv.upvotes_cast,0), 0)
        )
        +
        (case when coalesce(ubs.gold_badges,0) > 0 then 10 else 0 end) as quality_score
    from top_new_users u
    left join user_post_activity upa on upa.user_id = u.user_id
    left join accepted_answers aa on aa.user_id = u.user_id
    left join user_votes uv on uv.user_id = u.user_id
    left join user_badge_stats ubs on ubs.userid = u.user_id
),
activity_buckets as (
    select
        u.user_id,
        case
            when coalesce(upa.question_count,0) + coalesce(upa.answer_count,0) >= 100 then 'heavy'
            when coalesce(upa.question_count,0) + coalesce(upa.answer_count,0) >= 20 then 'medium'
            when coalesce(upa.question_count,0) + coalesce(upa.answer_count,0) > 0 then 'light'
            else 'none'
        end as activity_level
    from top_new_users u
    left join user_post_activity upa on upa.user_id = u.user_id
),
string_samples as (
    select
        u.user_id,
        concat_ws(' | ',
            coalesce(nullif(u.displayname,''), 'Anonymous'),
            regexp_replace(coalesce(nullif(u.location,''), 'Nowhere'), '\s+', ' ', 'g'),
            case when u.websiteurl_norm like 'http%' then u.websiteurl_norm else 'http://example.invalid' end
        ) as user_signature
    from top_new_users u
)
select
    u.user_id,
    u.displayname,
    u.reputation,
    cast(u.creationdate as varchar) as created_at,
    ab.activity_level,
    ss.user_signature,
    coalesce(ubs.total_badges,0) as total_badges,
    coalesce(ubs.gold_badges,0) as gold_badges,
    coalesce(ubs.silver_badges,0) as silver_badges,
    coalesce(ubs.bronze_badges,0) as bronze_badges,
    coalesce(upa.question_count,0) as questions,
    coalesce(upa.answer_count,0) as answers,
    coalesce(aa.accepted_answers_count,0) as accepted_answers,
    coalesce(upa.total_post_score,0) as total_post_score,
    round(coalesce(upa.avg_nonzero_score,0), 2) as avg_nonzero_score,
    coalesce(uv.upvotes_cast,0) as upvotes_cast,
    coalesce(uv.downvotes_cast,0) as downvotes_cast,
    coalesce(uv.favorites_cast,0) as favorites_cast,
    coalesce(uv.bounties_interactions,0) as bounty_interactions,
    coalesce(uv.bounty_total,0) as bounty_total,
    coalesce(pm.links_linked,0) as links_linked,
    coalesce(pm.links_duplicate,0) as links_duplicate,
    coalesce(uci.times_posts_closed,0) as times_posts_closed,
    cast(greatest(coalesce(upa.last_activity, timestamp '1900-01-01'), coalesce(ca.last_comment_date, timestamp '1900-01-01')) as date) as last_seen_content_date,
    coalesce(ca.comments_made,0) as comments_made,
    coalesce(ca.comment_score_total,0) as comment_score_total,
    coalesce(ubs.last_badge_date, timestamp '1900-01-01') as last_badge_date,
    coalesce(uci.last_closed_date, timestamp '1900-01-01') as last_closed_date,
    coalesce(ut.tagname, '(none)') as top_tag,
    coalesce(ut.tag_uses,0) as top_tag_uses,
    round(coalesce(uqs.quality_score,0), 2) as quality_score,
    case
        when coalesce(upa.answer_count,0) = 0 then null
        else round((coalesce(aa.accepted_answers_count,0) * 1.0 / nullif(upa.answer_count,0)) * 100, 2)
    end as answer_accept_rate_pct,
    case
        when coalesce(uv.upvotes_cast,0) + coalesce(uv.downvotes_cast,0) = 0 then 'N/A'
        when coalesce(uv.upvotes_cast,0) >= coalesce(uv.downvotes_cast,0) then 'positive'
        else 'negative'
    end as voting_polarity,
    case
        when lower(coalesce(u.location,'')) like '%remote%' or lower(coalesce(u.location,'')) like '%anywhere%' then 1
        when u.location is null then null
        else 0
    end as remote_hints
from top_new_users u
left join user_badge_stats ubs on ubs.userid = u.user_id
left join user_post_activity upa on upa.user_id = u.user_id
left join accepted_answers aa on aa.user_id = u.user_id
left join user_votes uv on uv.user_id = u.user_id
left join comment_activity ca on ca.user_id = u.user_id
left join post_link_metrics pm on pm.user_id = u.user_id
left join user_close_influence uci on uci.user_id = u.user_id
left join user_top_tag ut on ut.user_id = u.user_id and ut.rn = 1
left join user_quality_score uqs on uqs.user_id = u.user_id
left join activity_buckets ab on ab.user_id = u.user_id
left join string_samples ss on ss.user_id = u.user_id
where (
    coalesce(ubs.gold_badges,0) + coalesce(aa.accepted_answers_count,0) + coalesce(upa.answer_count,0)
) > 0
and (
    u.reputation > 1
    or exists (
        select 1
        from posts p2
        where p2.owneruserid = u.user_id
          and p2.posttypeid in (1,2)
          and coalesce(p2.score,0) >= 5
    )
)
union all
select
    u.user_id,
    u.displayname,
    u.reputation,
    cast(u.creationdate as varchar) as created_at,
    'none' as activity_level,
    ss.user_signature,
    0 as total_badges,
    0 as gold_badges,
    0 as silver_badges,
    0 as bronze_badges,
    0 as questions,
    0 as answers,
    0 as accepted_answers,
    0 as total_post_score,
    round(0.0, 2) as avg_nonzero_score,
    0 as upvotes_cast,
    0 as downvotes_cast,
    0 as favorites_cast,
    0 as bounty_interactions,
    0 as bounty_total,
    0 as links_linked,
    0 as links_duplicate,
    0 as times_posts_closed,
    cast(timestamp '1900-01-01' as date) as last_seen_content_date,
    0 as comments_made,
    0 as comment_score_total,
    timestamp '1900-01-01' as last_badge_date,
    timestamp '1900-01-01' as last_closed_date,
    '(none)' as top_tag,
    0 as top_tag_uses,
    round(0.0, 2) as quality_score,
    null as answer_accept_rate_pct,
    'N/A' as voting_polarity,
    null as remote_hints
from top_new_users u
left join string_samples ss on ss.user_id = u.user_id
where not exists (select 1 from posts p where p.owneruserid = u.user_id)
order by quality_score desc nulls last, reputation desc, user_id
limit 500;