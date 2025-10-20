with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.Date > u.CreationDate + interval '1 year'
),
LatestPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        p.LastActivityDate,
        rank() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as post_rank
    from Posts p
    where p.PostTypeId in (1, 2)
),
PostWithComments as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        p.LastActivityDate,
        c.CommentCount,
        coalesce(c.CommentScoreSum, 0) as CommentScoreSum
    from LatestPosts p
    left join (
        select
            PostId,
            count(*) as CommentCount,
            sum(coalesce(Score,0)) as CommentScoreSum
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(case when pl.LinkTypeId = 1 then 1 end) as LinkedCount,
        count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
),
PostHistoryAggregates as (
    select
        ph.PostId,
        count(distinct ph.UserId) as DistinctEditors,
        max(ph.CreationDate) as LastEditDate,
        sum(case when ph.PostHistoryTypeId in (10,11) then 1 else 0 end) as CloseReopenEvents
    from PostHistory ph
    group by ph.PostId
),
UserActivityStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        coalesce(sum(v.VoteCount), 0) as TotalVotesReceived,
        coalesce(avg(p.Score), 0) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        max(p.LastActivityDate) as LastActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            v.PostId,
            count(*) as VoteCount
        from Votes v
        group by v.PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
ComplexFilteredPosts as (
    select
        p.PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        p.LastActivityDate,
        p.CommentCount,
        p.CommentScoreSum,
        pla.LinkedCount,
        pla.DuplicateCount,
        pha.DistinctEditors,
        pha.LastEditDate,
        pha.CloseReopenEvents,
        u.Reputation,
        u.DisplayName as OwnerName,
        u.Views as OwnerViews,
        u.UpVotes as OwnerUpVotes,
        u.DownVotes as OwnerDownVotes,
        u.CreationDate as OwnerCreationDate
    from PostWithComments p
    left join PostLinkAggregates pla on pla.PostId = p.PostId
    left join PostHistoryAggregates pha on pha.PostId = p.PostId
    left join Users u on u.Id = p.OwnerUserId
    where
        p.Score > 5
        and (p.ViewCount > 1000 or p.CommentCount > 5)
        and (coalesce(pla.DuplicateCount,0) = 0 or coalesce(pla.LinkedCount,0) > 3)
        and coalesce(pha.DistinctEditors,0) > 1
        and (p.LastActivityDate > cast('2024-10-01' as date) - interval '6 months' or coalesce(pha.CloseReopenEvents,0) > 0)
),
AnswerScoresWindow as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
TopAnswers as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.AnswerRank,
        q.Title as QuestionTitle,
        q.Tags as QuestionTags,
        q.OwnerUserId as QuestionOwnerId
    from AnswerScoresWindow a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.AnswerRank <= 3
),
BadgeStringAgg as (
    select
        UserId,
        -- move ORDER BY expressions into the aggregate argument list for portability: aggregate by Name with array_agg then string_agg if needed
        string_agg(Name, ', ' order by Name) as BadgesList
    from Badges
    group by UserId
),
FinalUserStats as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.TotalPostScore,
        ua.TotalVotesReceived,
        ua.AvgPostScore,
        ua.MaxPostScore,
        ua.LastActivityDate,
        bs.BadgesList
    from UserActivityStats ua
    left join BadgeStringAgg bs on bs.UserId = ua.UserId
)
select
    cp.PostId,
    cp.Title,
    cp.Score,
    cp.ViewCount,
    cp.CommentCount,
    cp.CommentScoreSum,
    cp.LinkedCount,
    cp.DuplicateCount,
    cp.DistinctEditors,
    cp.LastEditDate,
    cp.CloseReopenEvents,
    cp.OwnerUserId,
    cp.OwnerName,
    cp.Reputation as OwnerReputation,
    cp.OwnerViews,
    cp.OwnerUpVotes,
    cp.OwnerDownVotes,
    cp.OwnerCreationDate,
    fa.Id as TopAnswerId,
    fa.Score as TopAnswerScore,
    fa.AnswerRank,
    fa.QuestionTitle,
    fa.QuestionTags,
    fus.QuestionsCount as OwnerQuestionsCount,
    fus.AnswersCount as OwnerAnswersCount,
    fus.TotalPostScore as OwnerTotalPostScore,
    fus.TotalVotesReceived as OwnerTotalVotesReceived,
    fus.AvgPostScore as OwnerAvgPostScore,
    fus.MaxPostScore as OwnerMaxPostScore,
    fus.LastActivityDate as OwnerLastActivityDate,
    fus.BadgesList as OwnerBadges
from ComplexFilteredPosts cp
left join TopAnswers fa on fa.ParentId = cp.PostId
left join FinalUserStats fus on fus.UserId = cp.OwnerUserId
where
    (
        cp.Tags is not null and
        (
            strpos(cp.Tags, '<sql>') > 0 or
            strpos(cp.Tags, '<performance>') > 0 or
            strpos(cp.Tags, '<optimization>') > 0
        )
    )
order by cp.Score desc, cp.ViewCount desc, cp.PostId
limit 100;