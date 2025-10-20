with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(v.VoteCount), 0) as TotalVotes,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsersCTE as (
    select * from RecursiveUserActivity where UserRank <= 100
),
PostDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        p.Body,
        case
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Answered'
            else 'Open'
        end as PostStatus,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank
    from Posts p
    inner join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.CreationDate >= (cast('2024-10-01' as date) - interval '1 year')
),
PostHistoryAggregates as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId in (10, 11)) as CloseReopenEvents,
        max(ph.CreationDate) as LastHistoryDate,
        string_agg(distinct pht.Name, ', ') as HistoryTypesInvolved
    from PostHistory ph
    inner join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    group by ph.PostId
),
AnswerWithVotes as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId = 2
    group by a.Id, a.ParentId, a.Score, a.CreationDate
),
DuplicateLinks as (
    select
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId,
        pl.CreationDate as LinkCreationDate,
        u.DisplayName as DuplicateOwner,
        u2.DisplayName as OriginalOwner
    from PostLinks pl
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = pl.PostId)
    left join Users u2 on u2.Id = (select OwnerUserId from Posts where Id = pl.RelatedPostId)
    where pl.LinkTypeId = 3
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadges
    from Badges b
    group by b.UserId
),
-- emulate lateral: pick top post per user
UserTopPost as (
    select pd.*
    from (
        select
            pd.*,
            row_number() over (partition by pd.OwnerUserId order by pd.Score desc nulls last) as rn
        from PostDetails pd
    ) pd
    where rn = 1
),
-- emulate lateral: pick top answer per question (for questions present in UserTopPost)
TopAnswerPerPost as (
    select aw.*
    from (
        select
            aw.*,
            row_number() over (partition by aw.QuestionId order by aw.AnswerScore desc nulls last) as rn
        from AnswerWithVotes aw
    ) aw
    where rn = 1
)
select
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.CommentCount,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    ubs.HasTagBasedBadges,
    pd.Id as SamplePostId,
    pd.PostTypeName,
    pd.Title,
    pd.Score,
    pd.ViewCount,
    pd.PostStatus,
    ph.CloseReopenEvents,
    ph.HistoryTypesInvolved,
    aw.AnswerId,
    aw.AnswerScore,
    aw.UpVotes,
    aw.DownVotes,
    aw.AnswerRank,
    dl.DuplicatePostId,
    dl.OriginalPostId,
    dl.LinkCreationDate,
    dl.DuplicateOwner,
    dl.OriginalOwner,
    concat(
        'User: ', coalesce(tu.DisplayName, 'Anonymous'), ' | ',
        'Reputation: ', tu.Reputation, ' | ',
        'Questions: ', tu.QuestionCount, ' | ',
        'Answers: ', tu.AnswerCount, ' | ',
        'Comments: ', tu.CommentCount, ' | ',
        'Badges(G/S/B): ', coalesce(ubs.GoldBadges,0), '/', coalesce(ubs.SilverBadges,0), '/', coalesce(ubs.BronzeBadges,0)
    ) as UserSummary,
    concat(
        'Post: ', coalesce(pd.Title, 'No Title'), ' | ',
        'Type: ', pd.PostTypeName, ' | ',
        'Score: ', pd.Score, ' | ',
        'Views: ', pd.ViewCount, ' | ',
        'Status: ', pd.PostStatus, ' | ',
        'Close/Reopen Events: ', coalesce(ph.CloseReopenEvents,0)
    ) as PostSummary
from TopUsersCTE tu
left join UserBadgeSummary ubs on ubs.UserId = tu.UserId
left join UserTopPost pd on pd.OwnerUserId = tu.UserId
left join PostHistoryAggregates ph on ph.PostId = pd.Id
left join TopAnswerPerPost aw on aw.QuestionId = pd.Id
left join DuplicateLinks dl on dl.DuplicatePostId = pd.Id
where tu.Reputation > 1000
order by tu.Reputation desc, pd.Score desc
limit 50;