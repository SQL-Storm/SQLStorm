with RecursiveUserBadgeCTE as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
),
LatestBadges_peruser as (
    select 
        UserId,
        DisplayName,
        BadgeName,
        Class,
        Date
    from RecursiveUserBadgeCTE
    where BadgeRank <= 3
),
TopQAPairs_base as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        ans.Id as AnswerId,
        ans.Score as AnswerScore,
        coalesce(ans.OwnerUserId, -1) as AnswererId,
        u.DisplayName as AnswererName,
        vt.Name as VoteType_OnAnswer,
        c.Id as CommentId,
        q.ClosedDate,
        q.LastActivityDate,
        ans.CreationDate
    from Posts q
    join Posts ans on ans.ParentId = q.Id and ans.PostTypeId = 2
    left join Votes v on v.PostId = ans.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    left join Comments c on c.PostId = q.Id
    left join Users u on u.Id = ans.OwnerUserId
    where q.PostTypeId = 1
),
TopQAPairs as (
    select
        QuestionId,
        Title,
        Tags,
        QuestionScore,
        ViewCount,
        AnswerId,
        AnswerScore,
        AnswererId,
        AnswererName,
        max(VoteType_OnAnswer) over (partition by AnswerId) as MaxVoteType_OnAnswer,
        QuestionCommentCount,
        IsRecentlyClosed,
        row_number() over (partition by QuestionId order by AnswerScore desc, CreationDate asc) as AnswerRank,
        ClosedDate,
        LastActivityDate
    from (
        select
            t.*,
            count(CommentId) over (partition by QuestionId) as QuestionCommentCount,
            case when ClosedDate is not null and ClosedDate > (LastActivityDate - interval '90' day) then 1 else 0 end as IsRecentlyClosed
        from TopQAPairs_base t
    ) s
),
AcceptedAnswerAgg as (
    select 
        q.Id as QuestionId,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        coalesce(u.DisplayName,'[deleted]') as AcceptedAnswerer,
        (select count(*) from Votes v where v.PostId = q.AcceptedAnswerId and v.VoteTypeId = 2) as AcceptedAnswerUpvoteCount,
        (select count(*) from Votes v where v.PostId = q.AcceptedAnswerId and v.VoteTypeId = 3) as AcceptedAnswerDownvoteCount
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
Combined as (
    select 
        tq.QuestionId,
        tq.Title,
        tq.Tags,
        tq.QuestionScore,
        tq.ViewCount,
        aagg.AcceptedAnswerId,
        aagg.AcceptedAnswerScore,
        aagg.AcceptedAnswerer,
        aagg.AcceptedAnswerUpvoteCount,
        aagg.AcceptedAnswerDownvoteCount,
        tq.AnswerId,
        tq.AnswerScore,
        tq.AnswererId,
        tq.AnswererName,
        tq.MaxVoteType_OnAnswer,
        tq.QuestionCommentCount,
        tq.IsRecentlyClosed,
        tq.ClosedDate,
        tq.LastActivityDate
    from TopQAPairs tq
    left join AcceptedAnswerAgg aagg on aagg.QuestionId = tq.QuestionId
    where tq.AnswerRank = 1
),
BadgeCounts as (
    select 
        u.Id as UserId,
        count(b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id
),
DuplicateCounts as (
    select pl.PostId, count(*) as DuplicateOfCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
Final as (
    select 
        c.QuestionId,
        c.Title,
        substring(c.Tags from 1 for 50) as SampledTags,
        c.QuestionScore,
        c.ViewCount,
        coalesce(dc.DuplicateOfCount, 0) as DuplicateHowMany,
        c.AcceptedAnswerId,
        c.AcceptedAnswerScore,
        c.AcceptedAnswerer,
        c.AcceptedAnswerUpvoteCount,
        c.AcceptedAnswerDownvoteCount,
        c.AnswerId,
        c.AnswerScore,
        c.AnswererId,
        c.AnswererName,
        b.BadgeCount,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        c.MaxVoteType_OnAnswer,
        c.QuestionCommentCount,
        c.IsRecentlyClosed,
        case 
            when c.LastActivityDate > (date '2024-10-01' - interval '30' day) and c.QuestionScore > 10 then 'Hot & Recent'
            when c.ClosedDate is not null then 'Closed Question'
            when c.ViewCount > 10000 then 'Popular Question'
            else 'Normal'
        end as QuestionClass
    from Combined c
    left join DuplicateCounts dc on dc.PostId = c.QuestionId
    left join BadgeCounts b on b.UserId = c.AnswererId
    left join Posts p2 on p2.Id = c.QuestionId
    order by c.QuestionScore desc, b.GoldBadges desc, c.AnswerScore desc
    limit 100
)
select * from Final;