-- {"query": "547.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3132} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl,''),'://',2)),''), 'no-domain') as website_domain,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
user_activity as (
    select
        u.user_id,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        count(*) filter (where c.id is not null) as total_comments,
        sum(vote_up) as upvotes_received,
        sum(vote_down) as downvotes_received,
        sum(favorites) as favorites_received,
        count(distinct case when p.posttypeid = 1 and p.acceptedanswerid is not null then p.id end) as questions_with_accept,
        count(distinct case when p.posttypeid = 2 and exists (
            select 1 from votes v2 where v2.postid = p.id and v2.votetypeid = 1
        ) then p.id end) as answers_accepted
    from recent_users u
    left join posts p
      on p.owneruserid = u.user_id
    left join lateral (
        select
            sum(case when v.votetypeid = 2 then 1 else 0 end) as vote_up,
            sum(case when v.votetypeid = 3 then 1 else 0 end) as vote_down,
            sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
        from votes v
        where v.postid = p.id
    ) vagg on true
    left join comments c
      on c.postid = p.id
    group by u.user_id
),
tagged_questions as (
    select
        p.id as question_id,
        p.owneruserid as owner_user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_array
    from posts p
    where p.posttypeid = 1
),
dominant_tags as (
    select
        tq.owner_user_id,
        lower(t.tagname) as tagname,
        count(*) as q_count,
        row_number() over (partition by tq.owner_user_id order by count(*) desc, lower(t.tagname)) as tag_rank
    from tagged_questions tq
    join tags t
      on lower(t.tagname) = any (tq.tag_array)
    group by tq.owner_user_id, lower(t.tagname)
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as badges_total,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges
    from badges b
    group by b.userid
),
question_edit_stats as (
    select
        p.owneruserid as user_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_on_own_posts,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_state_changes,
        max(ph.creationdate) as last_edit_date
    from posts p
    left join posthistory ph
      on ph.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
dup_clusters as (
    select
        q.owner_user_id,
        count(*) filter (where pl.linktypeid = 3) as dup_links_out,
        count(*) filter (where pl.linktypeid = 3 and p2.posttypeid = 1) as dup_to_questions
    from posts q
    left join postlinks pl
      on pl.postid = q.id
    left join posts p2
      on p2.id = pl.relatedpostid
    where q.posttypeid = 1
    group by q.owner_user_id
),
quality_score as (
    select
        ru.user_id,
        coalesce(ua.total_posts,0) as total_posts,
        coalesce(ua.total_comments,0) as total_comments,
        coalesce(ua.upvotes_received,0) as upvotes_received,
        coalesce(ua.downvotes_received,0) as downvotes_received,
        coalesce(ua.favorites_received,0) as favorites_received,
        coalesce(ua.questions_with_accept,0) as questions_with_accept,
        coalesce(ua.answers_accepted,0) as answers_accepted,
        coalesce(ub.badges_total,0) as badges_total,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(ub.tag_badges,0) as tag_badges,
        coalesce(qes.edits_on_own_posts,0) as edits_on_own_posts,
        coalesce(qes.mod_state_changes,0) as mod_state_changes,
        coalesce(dc.dup_links_out,0) as dup_links_out,
        coalesce(dc.dup_to_questions,0) as dup_to_questions,
        greatest(1, coalesce(ua.total_posts,0)) as denom_posts,
        round(
            (
                coalesce(ua.upvotes_received,0)*1.0
                - coalesce(ua.downvotes_received,0)*0.7
                + coalesce(ua.favorites_received,0)*0.9
                + coalesce(ub.gold_badges,0)*5
                + coalesce(ub.silver_badges,0)*2
                + coalesce(ub.bronze_badges,0)*1
                + coalesce(ua.answers_accepted,0)*3
                + coalesce(ua.questions_with_accept,0)*2
                - coalesce(dc.dup_links_out,0)*0.5
            ) / greatest(1, coalesce(ua.total_posts,0))
        , 4) as per_post_quality
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join question_edit_stats qes on qes.user_id = ru.user_id
    left join dup_clusters dc on dc.owner_user_id = ru.user_id
),
top_tag_per_user as (
    select dt.owner_user_id as user_id, dt.tagname as top_tag
    from dominant_tags dt
    where dt.tag_rank = 1
),
comment_sentiment as (
    select
        u.user_id,
        avg(length(c.text)) as avg_comment_len,
        sum(case when c.score >= 5 then 1 else 0 end) as high_score_comments,
        sum(case when position('thanks' in lower(coalesce(c.text,''))) > 0 then 1 else 0 end) as gratitude_comments
    from recent_users u
    left join comments c on c.userid = u.user_id
    group by u.user_id
),
recent_trending as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.creationdate >= now() - interval '30 days') as posts_30d,
        sum(p.viewcount) filter (where p.creationdate >= now() - interval '30 days') as views_30d,
        sum(p.score) filter (where p.creationdate >= now() - interval '30 days') as score_30d
    from posts p
    group by p.owneruserid
),
accepted_rate as (
    select
        u.user_id,
        case
            when q_count = 0 then null
            else round(accepted::numeric / q_count, 4)
        end as question_accept_rate
    from (
        select
            p.owneruserid as user_id,
            count(*) filter (where p.posttypeid = 1) as q_count,
            count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as accepted
        from posts p
        group by p.owneruserid
    ) s
),
rankings as (
    select
        qs.user_id,
        dense_rank() over (order by qs.per_post_quality desc nulls last) as r_quality,
        dense_rank() over (order by coalesce(rt.views_30d,0) desc) as r_views_30d,
        dense_rank() over (order by coalesce(ua.total_posts,0) desc) as r_posts,
        dense_rank() over (order by coalesce(ub.gold_badges,0), coalesce(ub.silver_badges,0), coalesce(ub.bronze_badges,0) desc) as r_badges_mix
    from quality_score qs
    left join user_activity ua on ua.user_id = qs.user_id
    left join user_badges ub on ub.user_id = qs.user_id
    left join recent_trending rt on rt.user_id = qs.user_id
),
final_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        coalesce(ru.location, 'Unknown') as location,
        ru.website_domain,
        qs.per_post_quality,
        ar.question_accept_rate,
        tt.top_tag,
        cs.avg_comment_len,
        cs.high_score_comments,
        cs.gratitude_comments,
        rt.posts_30d,
        rt.views_30d,
        rt.score_30d,
        ua.total_posts,
        ua.total_comments,
        ub.badges_total,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        qes.last_edit_date,
        r.r_quality,
        r.r_views_30d,
        r.r_posts,
        r.r_badges_mix
    from recent_users ru
    left join quality_score qs on qs.user_id = ru.user_id
    left join accepted_rate ar on ar.user_id = ru.user_id
    left join top_tag_per_user tt on tt.user_id = ru.user_id
    left join comment_sentiment cs on cs.user_id = ru.user_id
    left join recent_trending rt on rt.user_id = ru.user_id
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join question_edit_stats qes on qes.user_id = ru.user_id
    left join rankings r on r.user_id = ru.user_id
),
normed as (
    select
        f.*,
        ntile(10) over (order by coalesce(per_post_quality,0)) as dec_quality,
        ntile(10) over (order by coalesce(views_30d,0)) as dec_views,
        ntile(10) over (order by coalesce(total_posts,0)) as dec_posts,
        ntile(10) over (order by coalesce(badges_total,0)) as dec_badges
    from final_users f
),
filtered as (
    select *
    from normed
    where coalesce(total_posts,0) + coalesce(total_comments,0) > 0
      and coalesce(reputation,0) >= 1
      and (
            top_tag is not null
         or (dec_quality >= 5 and dec_views >= 5)
      )
),
agg_top_tags as (
    select
        top_tag,
        count(*) as user_count,
        avg(per_post_quality) as avg_quality,
        max(per_post_quality) as max_quality
    from filtered
    group by top_tag
),
top_users as (
    select
        f.user_id,
        f.displayname,
        f.top_tag,
        f.per_post_quality,
        f.views_30d,
        f.total_posts,
        row_number() over (
            partition by coalesce(f.top_tag, 'no-tag')
            order by f.per_post_quality desc nulls last, f.views_30d desc, f.total_posts desc, f.reputation desc
        ) as rn_by_tag
    from filtered f
)
select
    f.user_id,
    f.displayname,
    f.location,
    f.website_domain,
    coalesce(f.top_tag, 'no-tag') as top_tag,
    f.per_post_quality,
    f.question_accept_rate,
    f.avg_comment_len,
    f.gratitude_comments,
    f.high_score_comments,
    f.posts_30d,
    f.views_30d,
    f.score_30d,
    f.total_posts,
    f.total_comments,
    f.badges_total,
    f.gold_badges,
    f.silver_badges,
    f.bronze_badges,
    f.last_edit_date,
    f.r_quality,
    f.r_views_30d,
    f.r_posts,
    f.r_badges_mix,
    at.user_count as peers_in_tag,
    at.avg_quality as avg_quality_in_tag,
    at.max_quality as max_quality_in_tag,
    tu.rn_by_tag as rank_within_tag,
    case
        when f.per_post_quality is null then 'unknown'
        when f.per_post_quality >= (select percentile_disc(0.9) within group (order by per_post_quality) from filtered) then 'top-10%'
        when f.per_post_quality >= (select percentile_disc(0.75) within group (order by per_post_quality) from filtered) then 'top-25%'
        when f.per_post_quality >= (select percentile_disc(0.5) within group (order by per_post_quality) from filtered) then 'top-50%'
        else 'bottom-50%'
    end as quality_band
from filtered f
left join agg_top_tags at
  on at.top_tag is not distinct from f.top_tag
left join top_users tu
  on tu.user_id = f.user_id
where coalesce(f.r_quality, 1) <= 1000
  and (tu.rn_by_tag <= 50 or f.top_tag is null)
order by f.per_post_quality desc nulls last, f.views_30d desc, f.total_posts desc, f.reputation desc
limit 500;