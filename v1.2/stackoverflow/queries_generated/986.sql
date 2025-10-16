-- {"query": "986.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1965} 
with RecursivePostHierarchy as (
    select 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        0 as Level,
        cast(p.Title as varchar(1000)) as FullTitlePath,
        p.CreationDate
    from Posts p
    where p.ParentId is null

    union all

    select 
        c.Id,
        c.PostTypeId,
        c.ParentId,
        c.OwnerUserId,
        c.Score,
        r.Level + 1 as Level,
        cast(r.FullTitlePath || ' > ' || coalesce(c.Title, '[No Title]') as varchar(1000)),
        c.CreationDate
    from Posts c
    inner join RecursivePostHierarchy r on c.ParentId = r.Id
),
BadgeCountByUser as (
    select
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges,
        count(*) as TotalBadges
    from Badges
    group by UserId
),
UserActivityStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(b.GoldBadges, 0) as GoldBadges,
        coalesce(b.SilverBadges, 0) as SilverBadges,
        coalesce(b.BronzeBadges, 0) as BronzeBadges,
        coalesce(b.TotalBadges, 0) as TotalBadges,
        -- Average score of posts by user, excluding deleted posts (LastActivityDate is not null) and only Questions or Answers
        (
            select avg(p.Score)
            from Posts p
            where p.OwnerUserId = u.Id
              and p.PostTypeId in (1, 2)
              and p.LastActivityDate is not null
        ) as AvgPostScore,
        -- Total comments by user (join on Comments.UserId)
        (
            select count(*)
            from Comments c
            where c.UserId = u.Id
        ) as CommentCount,
        -- Days since last access or creation if last access null
        coalesce(
            date_part('day', u.LastAccessDate - u.CreationDate), 0
        ) as DaysActive
    from Users u
    left join BadgeCountByUser b on u.Id = b.UserId
),
TopTagsByPosts as (
    select 
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName,
        count(*) as TagPostCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by TagName
    having count(*) > 10
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.OwnerUserId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        a.OwnerUserId as AnswerOwner,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
RankedQuestionsWithAcceptedAnswer as (
    select
        qas.QuestionId,
        qas.Title,
        qas.QuestionCreation,
        qas.QuestionScore,
        qas.ViewCount,
        qas.AnswerCount,
        qas.OwnerUserId,
        aa.Score as AcceptedAnswerScore,
        aa.OwnerUserId as AcceptedAnswerOwner,
        coalesce(u.DisplayName, '[unknown user]') as QuestionOwnerName,
        coalesce(u2.DisplayName, '[unknown]') as AcceptedAnswerOwnerName
    from QuestionAnswerStats qas
    left join Posts q on qas.QuestionId = q.Id
    left join Posts aa on q.AcceptedAnswerId = aa.Id
    left join Users u on qas.OwnerUserId = u.Id
    left join Users u2 on aa.OwnerUserId = u2.Id
    where q.AcceptedAnswerId is not null
),
VotesSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
        count(*) as TotalVotes
    from Votes v
    inner join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
PostLinkStats as (
    select 
        pl.PostId,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
PostHistoryEdits as (
    select
        ph.PostId,
        count(*) as EditCount,
        max(ph.CreationDate) as LastEditDate,
        count(distinct ph.UserId) as DistinctEditors,
        sum(case when ph.PostHistoryTypeId in (10, 11) then 1 else 0 end) as CloseReopenEvents
    from PostHistory ph
    group by ph.PostId
)
select 
    rh.Level,
    rh.Id as PostId,
    rh.FullTitlePath,
    rh.CreationDate,
    rh.PostTypeId,
    rh.OwnerUserId,
    uas.DisplayName as OwnerName,
    uas.Reputation as OwnerReputation,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.TotalBadges,
    uas.CommentCount as OwnerCommentCount,
    coalesce(vs.UpVotes, 0) as UpVotes,
    coalesce(vs.DownVotes, 0) as DownVotes,
    coalesce(vs.Favorites, 0) as Favorites,
    coalesce(pls.LinkedCount, 0) as LinkedPosts,
    coalesce(pls.DuplicateCount, 0) as DuplicatePosts,
    coalesce(phe.EditCount, 0) as EditCount,
    coalesce(phe.DistinctEditors, 0) as DistinctEditors,
    coalesce(phe.CloseReopenEvents, 0) as CloseReopenEvents,
    -- Rank within posts by score descending partitioned by PostTypeId
    rank() over (partition by rh.PostTypeId order by coalesce(vs.UpVotes,0) - coalesce(vs.DownVotes,0) desc, rh.CreationDate asc) as PostScoreRank,
    -- Cumulative sum of answer count over questions ordered by score desc
    sum(coalesce(p.AnswerCount,0)) over (order by p.Score desc rows between unbounded preceding and current row) as CumAnswerCount,
    -- Check existence of tag 'sql' in Tags string (NULL-safe)
    case when rh.PostTypeId = 1 and rh.FullTitlePath is not null and exists (
        select 1 from Posts p2 where p2.Id = rh.Id and p2.Tags is not null and p2.Tags like '%<sql>%'
    ) then 1 else 0 end as HasSqlTag,
    -- Most frequent tag among posts with tag count > 10 and matches one of tags of this post
    (select TagName from TopTagsByPosts t where t.TagName in (
        select unnest(string_to_array(substring(p2.Tags from 2 for char_length(p2.Tags)-2), '><'))
        from Posts p2 where p2.Id = rh.Id
    ) order by TagPostCount desc limit 1) as MostPopularTagOfPost,
    -- String aggregation of badges names for owner user (top 3)
    (
        select string_agg(distinct b.Name || ' (' || b.Class || ')', ', ' order by b.Class limit 3)
        from Badges b where b.UserId = rh.OwnerUserId
    ) as OwnerTopBadges,
    -- Average post score for owner user
    uas.AvgPostScore,
    -- Days active for owner user
    uas.DaysActive

from RecursivePostHierarchy rh
inner join Posts p on rh.Id = p.Id
left join UserActivityStats uas on rh.OwnerUserId = uas.UserId
left join VotesSummary vs on rh.Id = vs.PostId
left join PostLinkStats pls on rh.Id = pls.PostId
left join PostHistoryEdits phe on rh.Id = phe.PostId

where rh.Level <= 2 -- limit depth for complexity control
order by rh.Level, PostScoreRank
limit 100;