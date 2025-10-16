-- {"query": "1470.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1542} 
with RecursiveUserPostScore as (
    select 
        u.Id as UserId,
        u.DisplayName, 
        p.Id as PostId,
        p.PostTypeId,
        coalesce(p.Score, 0) as PostScore,
        coalesce(p.ViewCount, 0) as Views,
        coalesce((select sum(v.BountyAmount) from Votes v where v.PostId = p.Id and v.VoteTypeId in (8,9)), 0) as TotalBounty,
        row_number() over(partition by u.Id order by p.Score desc nulls last, p.ViewCount desc) as UserPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
UserTopPosts as (
    select 
        usp.UserId,
        string_agg(distinct pt.Name, ', ') as PostTypesRepresented,
        sum(usp.PostScore) as TotalScore,
        sum(usp.Views) as TotalViews,
        sum(usp.TotalBounty) as TopPostBountySum,
        string_agg(
            concat('PostID:', usp.PostId, '_Score:', usp.PostScore, '_Views:', usp.Views),
            ' | '
            order by usp.PostScore desc nulls last
        ) as PostSummary
    from RecursiveUserPostScore usp
    join PostTypes pt on pt.Id = usp.PostTypeId
    where usp.UserPostRank <= 3 
    group by usp.UserId
),
UserBadgesCount as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        min(b.Date) as FirstBadgeDate
    from Badges b
    group by b.UserId
),
UserRecentBadges as (
    select distinct on (b.UserId) 
        b.UserId,
        b.Name as RecentBadgeName,
        b.Date as RecentBadgeDate
    from Badges b
    order by b.UserId, b.Date desc
),
QuestionsDetailed as (
    select 
        p.Id,
        p.Title, 
        p.CreationDate,
        p.Score, 
        p.ViewCount,
        p.AnswerCount,
        trim(Both '<>' from unnest(string_to_array(coalesce(p.Tags, ''), '><'))) as Tag,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as IsAccepted,
        u.DisplayName as OwnerDisplayName,
        row_number() over(partition by p.Id order by a.Score desc nulls last) as AnswerRank,
        coalesce((
            select count(*) 
            from PostLinks pl 
            where pl.PostId = p.Id and pl.LinkTypeId = 3
            ),0) as DuplicateCount
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
TopActiveQuestions as (
    select 
        q.Id,
        q.Title,
        q.ViewCount,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct q.Tag, ', ' order by q.Tag) as TagsList,
        q.AnswerCount,
        q.IsAccepted,
        q.DuplicateCount
    from QuestionsDetailed q
    left join Comments c on c.PostId = q.Id
    group by q.Id,q.Title,q.ViewCount,q.AnswerCount,q.IsAccepted,q.DuplicateCount
    having q.AnswerCount > 5 or count(c.Id) > 10
),
UserPairAnswerCount as (
    select
        u1.Id as User1Id,
        u2.Id as User2Id,
        count(distinct a1.Id) as CommonQuestionAnswers    
    from Users u1
    join Posts a1 on a1.OwnerUserId = u1.Id and a1.PostTypeId = 2
    join Posts q on q.Id = a1.ParentId and q.PostTypeId = 1
    join Posts a2 on a2.ParentId = q.Id and a2.PostTypeId = 2
    join Users u2 ON u2.Id = a2.OwnerUserId
    where u1.Id < u2.Id and abs(a1.Score - a2.Score) <= 5
    group by u1.Id, u2.Id
    having count(distinct a1.Id) > 2
),
FinalRanks as (
    select distinct 
        u.Id,
        u.DisplayName,
        urb.RecentBadgeName,
        ruc.GoldBadges,
        ruc.SilverBadges,
        ruc.BronzeBadges,
        etap.PostTypesRepresented,
        etap.TotalScore,
        etap.TotalViews,
        etap.TopPostBountySum,
        concat(
            'Gold:', ruc.GoldBadges::text, 
            '-Silver:', ruc.SilverBadges::text,
            '-Bronze:', ruc.BronzeBadges::text,
            '-Score:', etap.TotalScore::text
        ) as CompactStats
    from Users u
    left join UserBadgesCount ruc on ruc.UserId = u.Id
    left join UserRecentBadges urb on urb.UserId = u.Id
    left join UserTopPosts etap on etap.UserId = u.Id
    where etap.TotalScore is not null and (action_timestamp_part(u.LastAccessDate) > timestamp '2022-01-01' or etap.TopPostBountySum > 0)
    order by etap.TotalScore desc nulls last, ruc.GoldBadges desc, u.Reputation desc
    limit 25
)
select 
    fr.Id as UserId,
    fr.DisplayName,
    fr.RecentBadgeName,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.PostTypesRepresented,
    fr.TotalScore,
    fr.TotalViews,
    fr.TopPostBountySum,
    fr.CompactStats,
    taq.Id as HotQuestionId,
    taq.Title as HotQuestionTitle,
    coalesce(taq.TagsList, 'No Tags') as HotQuestionTags,
    taq.ViewCount as HotQuestionViews,
    taq.CommentCount as CommentCut,
    cast(taq.LastCommentDate as date) as LastCommentDay,
    concat(u1.DisplayName, ' & ', u2.DisplayName) as PeerPair,
    uppc.CommonQuestionAnswers as CommonAnswersCount
from FinalRanks fr
left join TopActiveQuestions taq on taq.Id = (
    select q4.Id from TopActiveQuestions q4 
    order by q4.ViewCount desc limit 1 offset (fr.Id % 10)
)
left join UserPairAnswerCount uppc on uppc.User1Id = fr.Id
left join Users u1 on u1.Id = uppc.User1Id
left join Users u2 on u2.Id = uppc.User2Id
order by fr.TotalScore desc, taq.ViewCount desc nulls last, CommonAnswersCount desc nulls last
limit 50;