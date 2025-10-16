-- {"query": "580.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1301} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(vt.Name = 'UpMod'::text)::int as TotalUpVotes,
        sum(vt.Name = 'DownMod'::text)::int as TotalDownVotes,
        row_number() over (partition by u.Location order by u.Reputation desc) as RankByLocation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
UserBadgeSummary as (
    select 
        b.UserId,
        count(*) as TotalBadges,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadge
    from Badges b
    group by b.UserId
),
TopPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1, 2) -- questions and answers
      and p.Score > 0
),
PostWithAcceptedAnswer as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner,
        a.CreationDate as AnswerCreation,
        u.DisplayName as AnswerOwnerName
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
UserRecentActivity as (
    select 
        u.Id as UserId,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(ph.CreationDate) as LastEditDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.HasTagBasedBadge,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.RankByLocation,
    tp.Id as TopPostId,
    tp.Title as TopPostTitle,
    tp.Score as TopPostScore,
    tp.ViewCount as TopPostViews,
    pwa.AcceptedAnswerId,
    pwa.AnswerOwnerName as AcceptedAnswerOwnerName,
    pwa.AcceptedAnswerScore,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateRelatedPostTitle,
    ura.LastPostDate,
    ura.LastCommentDate,
    ura.LastEditDate,
    case 
        when ua.Reputation > 10000 then 'Legendary'
        when ua.Reputation > 5000 then 'Expert'
        when ua.Reputation > 1000 then 'Intermediate'
        else 'Beginner'
    end as ReputationTier,
    -- Complex string manipulation with NULL logic
    concat_ws(' | ',
        ua.DisplayName,
        coalesce(nullif(ua.Location, ''), 'No Location'),
        'Q:'+cast(ua.QuestionCount as varchar),
        'A:'+cast(ua.AnswerCount as varchar),
        'Badges: G' || cast(ubs.GoldBadges as varchar) || ' S' || cast(ubs.SilverBadges as varchar) || ' B' || cast(ubs.BronzeBadges as varchar)
    ) as UserSummary
from RecursiveUserActivity ua
left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
left join TopPosts tp on tp.OwnerUserId = ua.UserId and tp.ScoreRank = 1
left join PostWithAcceptedAnswer pwa on pwa.AcceptedAnswerOwner = ua.UserId
left join DuplicateLinks dup on dup.PostId = tp.Id
left join UserRecentActivity ura on ura.UserId = ua.UserId
where ua.QuestionCount > 0
  and (ua.TotalUpVotes - ua.TotalDownVotes) > 10
order by ua.Reputation desc, ua.QuestionCount desc
limit 100;