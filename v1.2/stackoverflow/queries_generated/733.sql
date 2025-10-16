-- {"query": "733.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1554} 
with RecursiveUserPosts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
UserBadgeCounts as (
    select 
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
PostLinkAggregates as (
    select 
        pl.PostId,
        sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as DuplicateLinks,
        sum(case when lt.Name = 'Linked' then 1 else 0 end) as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
PostVoteStats as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotes,
        sum(case when vt.Name = 'BountyStart' then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
CTE_QuestionsWithAnswers AS (
    select 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate as QuestionCreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        max(a.CreationDate) as LatestAnswerDate
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.AcceptedAnswerId
),
CTE_AnswersWithQuestions AS (
    select 
        a.Id as AnswerId,
        a.OwnerUserId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
),
CTE_CommentsWithUserInfo AS (
    select 
        c.Id as CommentId,
        c.PostId,
        c.Score as CommentScore,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        u.Id as UserId,
        u.DisplayName,
        u.Reputation
    from Comments c
    left join Users u on u.Id = c.UserId
),
RankedUserPosts AS (
    select 
        rup.*,
        case 
            when rup.PostTypeId = 1 then 'Question'
            when rup.PostTypeId = 2 then 'Answer'
            when rup.PostTypeId in (3,4,5,6,7,8) then 'Other'
            else 'Unknown'
        end as PostTypeName
    from RecursiveUserPosts rup
    where rup.RecentPostRank <= 5
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.DistinctBadges,
    q.QuestionId,
    q.Title as QuestionTitle,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.Tags,
    q.AnswerCount,
    q.MaxAnswerScore,
    q.AvgAnswerScore,
    q.LatestAnswerDate,
    pl.DuplicateLinks,
    pl.LinkedPosts,
    pv.UpVotes,
    pv.DownVotes,
    pv.FavoriteVotes,
    pv.TotalBounty,
    cwi.CommentCount,
    cwi.LatestCommentDate,
    cwi.TopCommentUserDisplayName,
    r.PostId,
    r.PostTypeName,
    r.CreationDate as PostCreationDate,
    r.Score as PostScore,
    -- Complex string and null logic: concat tags and user display name safely
    concat_ws(' | ', coalesce(q.Tags, 'NoTags'), coalesce(u.DisplayName, 'Anonymous')) as TagUserConcat,
    -- Window function: rank posts per user by score
    rank() over (partition by u.Id order by r.Score desc nulls last) as PostScoreRank,
    -- Exists correlated subquery: does user have a gold badge named 'Legendary'
    exists (
        select 1 from Badges b2 
        where b2.UserId = u.Id and b2.Class = 1 and b2.Name = 'Legendary'
    ) as HasLegendaryBadge,
    -- Complex predicate example: user active if last access within 90 days and reputation > 5000 or has silver badges > 10
    case 
        when (u.LastAccessDate > now() - interval '90 days' and u.Reputation > 5000) or ub.SilverBadges > 10 then 'Active'
        else 'Inactive'
    end as UserActivityStatus
from Users u
left join UserBadgeCounts ub on ub.UserId = u.Id
left join CTE_QuestionsWithAnswers q on q.OwnerUserId = u.Id
left join PostLinkAggregates pl on pl.PostId = q.QuestionId
left join PostVoteStats pv on pv.PostId = q.QuestionId
left join (
    select 
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LatestCommentDate,
        max(u.DisplayName) filter (where c.UserId is not null order by c.Score desc nulls last) as TopCommentUserDisplayName
    from Comments c
    left join Users u on u.Id = c.UserId
    group by c.PostId
) cwi on cwi.PostId = q.QuestionId
left join RankedUserPosts r on r.UserId = u.Id
where u.Reputation > 1000
and (q.AnswerCount is null or q.AnswerCount > 0)
order by u.Reputation desc, q.QuestionCreationDate desc
limit 100;