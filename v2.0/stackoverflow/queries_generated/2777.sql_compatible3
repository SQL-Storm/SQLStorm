with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct case when b.TagBased = true then b.Name end) as TagBasedBadges
    from Badges b
    group by b.UserId
),
PostCommentInfo as (
    select
        c.PostId,
        count(*) as TotalComments,
        max(c.Score) as MaxCommentScore,
        string_agg(distinct coalesce(nullif(trim(c.UserDisplayName), ''), 'Anonymous'), ', ') as Commenters
    from Comments c
    group by c.PostId
),
PostWithHistory as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.ClosedDate,
        p.AcceptedAnswerId,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.Comment as HistoryComment
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
UserActivityRanked as (
    select
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.CreationDate,
        rua.LastAccessDate,
        rua.PostId,
        rua.PostTypeId,
        rua.Score,
        rua.ViewCount,
        rua.AnswerCount,
        rua.FavoriteCount,
        rua.RecentPostRank,
        coalesce(ub.GoldBadges, 0) as GoldBadges,
        coalesce(ub.SilverBadges, 0) as SilverBadges,
        coalesce(ub.BronzeBadges, 0) as BronzeBadges,
        coalesce(ub.TagBasedBadges, 0) as TagBasedBadges,
        pci.TotalComments,
        pci.MaxCommentScore,
        pci.Commenters
    from RecursiveUserActivity rua
    left join UserBadgeCounts ub on ub.UserId = rua.UserId
    left join PostCommentInfo pci on pci.PostId = rua.PostId
),
AcceptedAnswerScores as (
    select
        q.Id as QuestionId,
        q.AcceptedAnswerId,
        ans.Score as AcceptedAnswerScore,
        ans.CreationDate as AcceptedAnswerCreationDate
    from Posts q
    left join Posts ans on ans.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
),
QuestionsWithDuplicates as (
    select distinct
        pq.Id as QuestionId,
        pq.Title,
        pq.Score,
        pq.AnswerCount,
        pl.RelatedPostId as DuplicateId
    from Posts pq
    left join PostLinks pl on pl.PostId = pq.Id and pl.LinkTypeId = 3
    where pq.PostTypeId = 1
),
QuestionsTagsExpanded as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TopTagsWithAggregate as (
    select
        te.Tag,
        count(*) as UsageCount,
        avg(p.Score) as AvgScore,
        max(p.ViewCount) as MaxViews,
        count(distinct p.OwnerUserId) filter (where p.OwnerUserId is not null) as DistinctUsers
    from QuestionsTagsExpanded te
    join Posts p on p.Id = te.PostId
    group by te.Tag
    having count(*) > 100
),
WindowedUserActivity as (
    select
        uar.UserId,
        uar.DisplayName,
        uar.Reputation,
        uar.CreationDate,
        uar.LastAccessDate,
        uar.PostId,
        uar.PostTypeId,
        uar.Score,
        uar.ViewCount,
        uar.AnswerCount,
        uar.FavoriteCount,
        uar.RecentPostRank,
        uar.GoldBadges,
        uar.SilverBadges,
        uar.BronzeBadges,
        uar.TagBasedBadges,
        uar.TotalComments,
        uar.MaxCommentScore,
        uar.Commenters,
        rank() over (partition by uar.UserId order by uar.Score desc nulls last) as PostScoreRank,
        dense_rank() over (order by coalesce(uar.GoldBadges, 0) desc, coalesce(uar.Reputation, 0) desc) as UserRank
    from UserActivityRanked uar
),
FinalResult as (
    select distinct
        wua.UserId,
        wua.DisplayName,
        wua.Reputation,
        wua.GoldBadges,
        wua.SilverBadges,
        wua.BronzeBadges,
        coalesce(wua.TagBasedBadges, 0) as TagBasedBadges,
        wua.PostId,
        wua.PostTypeId,
        wua.Score,
        wua.ViewCount,
        wua.AnswerCount,
        wua.FavoriteCount,
        wua.RecentPostRank,
        wua.TotalComments,
        wua.MaxCommentScore,
        wua.Commenters,
        aac.AcceptedAnswerScore,
        aac.AcceptedAnswerCreationDate,
        qd.DuplicateId,
        ttwa.Tag as FrequentTag,
        ttwa.UsageCount as TagUsageCount,
        ttwa.AvgScore as TagAvgScore,
        ttwa.MaxViews as TagMaxViews,
        ttwa.DistinctUsers as TagDistinctUsers,
        (case when wua.PostTypeId = 1 and aac.AcceptedAnswerId is null then 1 else 0 end) as IsUnanswered,
        case when (select p.ClosedDate from Posts p where p.Id = wua.PostId) is null then 0 else 1 end as IsClosed,
        coalesce(
            concat_ws(
                ' | ',
                wua.DisplayName,
                nullif(cast(coalesce(wua.TagBasedBadges, 0) as text), '0'),
                coalesce(cast(qd.DuplicateId as text), 'NoDuplicate')
            ),
            'UnknownUser | 0 | NoDuplicate'
        ) as UserTagDuplicateInfo,
        wua.UserRank,
        wua.PostScoreRank
    from WindowedUserActivity wua
    left join AcceptedAnswerScores aac on aac.QuestionId = wua.PostId
    left join QuestionsWithDuplicates qd on qd.QuestionId = wua.PostId
    left join TopTagsWithAggregate ttwa on ttwa.Tag = (
        select qte.Tag
        from QuestionsTagsExpanded qte
        where qte.PostId = wua.PostId
        order by qte.Tag
        limit 1
    )
    where wua.RecentPostRank <= 5
)
select *
from FinalResult
where
    (Reputation > 5000 or GoldBadges > 5)
    and Score >= (
        select percentile_cont(0.5) within group (order by p.Score)
        from Posts p
        where p.PostTypeId = FinalResult.PostTypeId
    )
order by UserRank, PostScoreRank
limit 100;