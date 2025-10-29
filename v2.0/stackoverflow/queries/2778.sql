-- {"query": "2778.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1657}
with recursive RecursiveUserBadgeCTE as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000 and b.Class is not null

    union all

    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.BadgeName,
        r.Class,
        r.BadgeRank + 1
    from RecursiveUserBadgeCTE r
    where r.BadgeRank < 3
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        count(a.Id) filter (where a.PostTypeId = 2) as AnswerCount,
        avg(a.Score) filter (where a.PostTypeId = 2) as AvgAnswerScore,
        max(a.CreationDate) filter (where a.PostTypeId = 2) as LastAnswerDate
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score
),
UserActivityRank as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(p.Id) filter (where p.PostTypeId=1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId=2) as AnswerCount,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
TopTagsExploded as (
    -- portable recursive splitter for Posts.Tags into rows
    select
        p.Id as PostId,
        p.OwnerUserId,
        case
            when position('><' in substring(p.Tags from 2 for char_length(p.Tags)-2)) = 0 then substring(p.Tags from 2 for char_length(p.Tags)-2)
            else substring(p.Tags from 2 for char_length(p.Tags)-2) end as remaining,
        cast(null as varchar) as tag,
        0 as step
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null and p.Tags <> ''
    union all
    select
        te.PostId,
        te.OwnerUserId,
        case
            when position('><' in te.remaining) = 0 then ''
            else substring(te.remaining from position('><' in te.remaining)+2)
        end,
        case
            when position('><' in te.remaining) = 0 then te.remaining
            else substring(te.remaining from 1 for position('><' in te.remaining)-1)
        end,
        te.step + 1
    from TopTagsExploded te
    where te.remaining <> ''
),
TopTagsPerUser_Final as (
    select
        OwnerUserId,
        tag as Tag,
        count(*) as TagUsage
    from TopTagsExploded
    where tag is not null and tag <> ''
    group by OwnerUserId, tag
),
UserTopTagRank as (
    select
        TagOwner.OwnerUserId,
        TagOwner.Tag,
        TagOwner.TagUsage,
        row_number() over (partition by TagOwner.OwnerUserId order by TagOwner.TagUsage desc) as TagRank
    from TopTagsPerUser_Final TagOwner
),
DuplicatesAndLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        p.Title as PostTitle,
        rp.Title as RelatedPostTitle
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    inner join Posts p on p.Id = pl.PostId
    inner join Posts rp on rp.Id = pl.RelatedPostId
    where lt.Name in ('Duplicate','Linked')
),
FilteredVotes as (
    select
        v.PostId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        count(*) filter (where v.VoteTypeId = 5) as FavoriteVotes,
        sum(v.BountyAmount) as TotalBounty
    from Votes v
    group by v.PostId
),
QuestionsWithCommentCounts as (
    select
        p.Id as PostId,
        p.Title,
        p.OwnerUserId,
        count(c.Id) as CommentCount
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId
),
ComplexFilteredQuestions as (
    select
        q.PostId,
        q.Title,
        q.OwnerUserId,
        q.CommentCount,
        fs.UpVotes,
        fs.DownVotes,
        fs.FavoriteVotes,
        fs.TotalBounty,
        qs.AnswerCount,
        qs.AvgAnswerScore,
        qs.LastAnswerDate,
        ua.ReputationRank,
        ua.QuestionCount,
        ua.AnswerCount as UserAnswerCount,
        u.DisplayName as OwnerName,
        ut.Tag as TopUserTag,
        ub.BadgeName,
        ub.Class as BadgeClass
    from QuestionsWithCommentCounts q
    left join FilteredVotes fs on fs.PostId = q.PostId
    left join QuestionAnswerStats qs on qs.QuestionId = q.PostId
    left join UserActivityRank ua on ua.UserId = q.OwnerUserId
    left join Users u on u.Id = q.OwnerUserId
    left join UserTopTagRank ut on ut.OwnerUserId = q.OwnerUserId and ut.TagRank = 1
    left join RecursiveUserBadgeCTE ub on ub.UserId = q.OwnerUserId and ub.BadgeRank = 1
    where q.CommentCount > 2 and (fs.UpVotes - coalesce(fs.DownVotes,0)) > 5
    group by
        q.PostId,
        q.Title,
        q.OwnerUserId,
        q.CommentCount,
        fs.UpVotes,
        fs.DownVotes,
        fs.FavoriteVotes,
        fs.TotalBounty,
        qs.AnswerCount,
        qs.AvgAnswerScore,
        qs.LastAnswerDate,
        ua.ReputationRank,
        ua.QuestionCount,
        ua.AnswerCount,
        u.DisplayName,
        ut.Tag,
        ub.BadgeName,
        ub.Class
),
RankedQuestions as (
    select
        cfq.PostId,
        cfq.Title,
        cfq.OwnerUserId,
        cfq.CommentCount,
        cfq.UpVotes,
        cfq.DownVotes,
        cfq.FavoriteVotes,
        cfq.TotalBounty,
        cfq.AnswerCount,
        cfq.AvgAnswerScore,
        cfq.LastAnswerDate,
        cfq.ReputationRank,
        cfq.QuestionCount,
        cfq.UserAnswerCount,
        cfq.OwnerName,
        cfq.TopUserTag,
        cfq.BadgeName,
        cfq.BadgeClass,
        row_number() over (partition by cfq.OwnerUserId order by cfq.AnswerCount desc, cfq.UpVotes desc) as UserQuestionRank
    from ComplexFilteredQuestions cfq
),
FinalSelection as (
    select
        rq.PostId,
        rq.Title,
        rq.OwnerUserId,
        rq.OwnerName,
        rq.ReputationRank,
        rq.QuestionCount,
        rq.UserAnswerCount,
        rq.CommentCount,
        rq.UpVotes,
        rq.DownVotes,
        rq.FavoriteVotes,
        rq.TotalBounty,
        rq.AnswerCount,
        rq.AvgAnswerScore,
        rq.LastAnswerDate,
        rq.TopUserTag,
        case 
            when rq.BadgeClass = 1 then 'Gold'
            when rq.BadgeClass = 2 then 'Silver'
            when rq.BadgeClass = 3 then 'Bronze'
            else 'None'
        end as TopBadgeClass,
        rq.BadgeName,
        rq.UserQuestionRank
    from RankedQuestions rq
    where rq.UserQuestionRank <= 2
)
select 
    fsq.PostId,
    fsq.Title,
    fsq.OwnerName,
    fsq.ReputationRank,
    fsq.QuestionCount,
    fsq.UserAnswerCount,
    fsq.CommentCount,
    fsq.UpVotes,
    fsq.DownVotes,
    fsq.FavoriteVotes,
    fsq.TotalBounty,
    fsq.AnswerCount,
    round(cast(fsq.AvgAnswerScore as numeric),2) as AvgAnswerScore,
    fsq.LastAnswerDate,
    coalesce(fsq.TopUserTag, 'NoTag') as TopUserTag,
    fsq.TopBadgeClass,
    fsq.BadgeName,
    case 
        when fsq.CommentCount > 10 and fsq.AnswerCount > 5 and fsq.UpVotes > 20 then 'High Engagement' 
        when fsq.CommentCount between 3 and 10 and fsq.AnswerCount between 1 and 5 then 'Moderate Engagement'
        else 'Low Engagement'
    end as EngagementLevel
from FinalSelection fsq
order by fsq.ReputationRank, fsq.UpVotes desc, fsq.CommentCount desc;