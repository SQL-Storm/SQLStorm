-- {"query": "508.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1371} 
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
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc) as RankInLocation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
    union all
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown'),
        0,
        0,
        0,
        0,
        0,
        0,
        1
    from Users u
    where u.Reputation <= 1000
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
        p.AcceptedAnswerId,
        p.ParentId,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    where p.CreationDate >= cast('2024-10-01' as date) - interval '1 year'
),
QuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation,
        case when a.Score > q.Score then 1 else 0 end as AnswerBetterThanQuestion,
        lag(a.Score) over (partition by q.Id order by a.Score desc) as PrevAnswerScore,
        lead(a.Score) over (partition by q.Id order by a.Score desc) as NextAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate as LinkCreated,
        lt.Name as LinkTypeName
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
),
UserVoteStats as (
    select
        v.UserId,
        vt.Name as VoteTypeName,
        count(*) as VoteCount,
        sum(coalesce(v.BountyAmount, 0)) as TotalBounty
    from Votes v
    inner join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId, vt.Name
),
UserActivitySummary as (
    select
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.Location,
        rua.QuestionCount,
        rua.AnswerCount,
        rua.CommentCount,
        rua.GoldBadges,
        rua.SilverBadges,
        rua.BronzeBadges,
        coalesce(uvs.VoteCount, 0) as TotalVotes,
        coalesce(uvs.TotalBounty, 0) as TotalBountyAwarded,
        (rua.GoldBadges * 3 + rua.SilverBadges * 2 + rua.BronzeBadges) as BadgeScore
    from RecursiveUserActivity rua
    left join (
        select UserId, sum(VoteCount) as VoteCount, sum(TotalBounty) as TotalBounty
        from UserVoteStats
        group by UserId
    ) uvs on uvs.UserId = rua.UserId
)
select
    uas.DisplayName,
    uas.Location,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.TotalVotes,
    uas.TotalBountyAwarded,
    uas.BadgeScore,
    qwa.QuestionId,
    qwa.Title as QuestionTitle,
    qwa.Tags as QuestionTags,
    qwa.QuestionScore,
    qwa.QuestionViews,
    qwa.AnswerId,
    qwa.AnswerScore,
    qwa.AnswerCreationDate,
    qwa.AnswerOwnerName,
    qwa.AnswerOwnerReputation,
    qwa.AnswerBetterThanQuestion,
    dl.LinkCreated as DuplicateLinkDate,
    dl.PostTitle as DuplicatePostTitle,
    dl.RelatedPostTitle as DuplicateRelatedPostTitle,
    dl.LinkTypeName
from UserActivitySummary uas
left join QuestionsWithAnswers qwa on qwa.AnswerOwnerName = uas.DisplayName
left join DuplicateLinks dl on dl.PostId = qwa.QuestionId
where uas.BadgeScore > 10
  and qwa.AnswerBetterThanQuestion = 1
  and (dl.LinkCreated is null or dl.LinkCreated > qwa.AnswerCreationDate)
order by uas.BadgeScore desc, uas.Reputation desc, qwa.QuestionScore desc
limit 100;