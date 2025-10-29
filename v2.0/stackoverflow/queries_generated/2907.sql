-- {"query": "2907.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1551} 
with RecursiveTagCount as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.AnswerCount, 0) + coalesce(p.CommentCount, 0) as EngagementScore,
        1 as Depth
    from
        Tags t
    left join
        Posts p on p.Id = t.ExcerptPostId
    where
        t.TagName is not null

    union all

    select
        t.Id,
        t.TagName,
        rtc.EngagementScore + coalesce(p.CommentCount, 0),
        rtc.Depth + 1
    from
        RecursiveTagCount rtc
    join
        Tags t on t.Id = rtc.TagId
    left join
        Posts p on p.Id = t.WikiPostId
    where
        rtc.Depth < 2
),
UserReputations AS (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        row_number() over (partition by u.Location order by u.Reputation desc) as RankByLocation,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) as HighestBadgeClass
    from
        Users u
    left join
        Badges b on b.UserId = u.Id
    where
        u.Location is not null
        and u.Reputation > 100 
    group by
        u.Id, u.DisplayName, u.Reputation, u.Location
),
TopPostsWithDetails AS (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Tags,
        (select count(1) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(1) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(1) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as RankByUser
    from
        Posts p
    left join
        Users u on u.Id = p.OwnerUserId
    where
        p.PostTypeId = 1 -- questions only
        and p.Score > 5
        and p.ViewCount > 100
),
MarkDuplicateRelations AS (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p.Title as RelatedPostTitle
    from
        PostLinks pl
    join
        LinkTypes lt on lt.Id = pl.LinkTypeId
    join
        Posts p on p.Id = pl.RelatedPostId
    where 
        lt.Name = 'Duplicate'
),
FilteredPostHistory AS (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name as HistoryTypeName,
        ph.UserId,
        us.DisplayName as EditorName,
        ph.CreationDate,
        ph.Comment,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from
        PostHistory ph
    join
        PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    left join
        Users us on us.Id = ph.UserId
    where 
        ph.PostHistoryTypeId in (4,5,6,10,11,19,20)
),
LatestEdits AS (
    select
        PostId,
        HistoryTypeName,
        EditorName,
        CreationDate,
        Comment
    from
        FilteredPostHistory
    where
        rn = 1
),
AnswerScoresAndRanks AS (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName,
        rank() over (partition by a.ParentId order by a.Score desc) as RankByScore,
        dense_rank() over (partition by a.ParentId order by a.OwnerUserId) as OwnerRank
    from
        Posts a
    left join
        Users u on u.Id = a.OwnerUserId
    where
        a.PostTypeId = 2
)
select 
    tp.Id as QuestionId,
    tp.Title,
    tp.CreationDate,
    tp.Score as QuestionScore,
    tp.ViewCount,
    tp.OwnerUserId,
    tp.OwnerName,
    tp.Tags,
    tp.CommentCount,
    tp.UpVotes,
    tp.DownVotes,
    ur.DisplayName as TopUserInLocation,
    ur.Location,
    ur.Reputation as UserReputation,
    ur.BadgeCount,
    ur.HighestBadgeClass,
    le.HistoryTypeName as LastEditType,
    le.EditorName as LastEditor,
    le.CreationDate as LastEditDate,
    mdr.RelatedPostId as DuplicateOfPostId,
    mdr.RelatedPostTitle as DuplicateOfPostTitle,
    asa.AnswerId,
    asa.AnswerScore,
    asa.AnswerOwnerName,
    asa.RankByScore as AnswerRankByScore
from
    TopPostsWithDetails tp
left join
    UserReputations ur on ur.Id = tp.OwnerUserId and ur.RankByLocation = 1
left join
    LatestEdits le on le.PostId = tp.Id
left join
    MarkDuplicateRelations mdr on mdr.PostId = tp.Id
left join
    AnswerScoresAndRanks asa on asa.QuestionId = tp.Id and asa.RankByScore = 1
where
    (tp.UpVotes - tp.DownVotes) > 5
    and (
        tp.Tags ilike '%<sql>%'
        or tp.Tags ilike '%<database>%'
    )
union
select
    p.Id as QuestionId,
    p.Title,
    p.CreationDate,
    p.Score as QuestionScore,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName as OwnerName,
    p.Tags,
    (select count(1) from Comments c where c.PostId = p.Id),
    (select count(1) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2),
    (select count(1) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3),
    ur.DisplayName,
    ur.Location,
    ur.Reputation,
    ur.BadgeCount,
    ur.HighestBadgeClass,
    null,
    null,
    null,
    null,
    null,
    null,
    null
from
    Posts p
left join
    Users u on u.Id = p.OwnerUserId
left join
    UserReputations ur on ur.Id = p.OwnerUserId
where
    p.PostTypeId = 1
    and p.Score > 100
    and not exists (
        select 1
        from PostLinks pl2
        where pl2.PostId = p.Id and pl2.LinkTypeId = 3
    )
order by
    QuestionScore desc nulls last,
    ViewCount desc nulls last,
    CreationDate desc
limit 100;