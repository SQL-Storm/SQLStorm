-- {"query": "4034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1721} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
    union all
    select 
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.CreationDate,
        r.LastAccessDate,
        r.Location,
        r.QuestionsPosted,
        r.AnswersPosted,
        r.CommentsMade,
        r.UpVotesReceived,
        r.DownVotesReceived,
        r.UserRank + 1
    from RecursiveUserActivity r
    where r.UserRank < 3
), LatestPostVotes AS (
    select 
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        v.VoteTypeId,
        v.CreationDate as VoteDate,
        v.BountyAmount
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId in (1, 2)
), TopTags AS (
    select 
        t.Id, 
        t.TagName, 
        t.Count,
        p.Id as QuestionPostId,
        p.OwnerUserId,
        p.Score as PostScore,
        row_number() over (partition by t.Id order by p.Score desc nulls last) as RankByScore
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like '%' || t.TagName || '%'
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
), UserBadgeCounts AS (
    select 
        b.UserId,
        b.Class,
        count(distinct b.Id) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
), DuplicateQuestions AS (
    select 
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalQuestionTitle,
        p2.Title as DuplicateQuestionTitle,
        l.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes l on l.Id = pl.LinkTypeId and l.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.RelatedPostId
    join Posts p2 on p2.Id = pl.PostId
    where p1.PostTypeId = 1 and p2.PostTypeId = 1
), QuestionCloseReasons AS (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        max(ph.CreationDate) as LastCloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
), UserActivitySummary AS (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(qs.QuestionsAsked, 0) as QuestionsAsked,
        coalesce(ans.AnswersGiven, 0) as AnswersGiven,
        coalesce(comm.CommentsMade, 0) as CommentsMade,
        coalesce(ub.BronzeBadges, 0) as BronzeBadges,
        coalesce(ub.SilverBadges, 0) as SilverBadges,
        coalesce(ub.GoldBadges, 0) as GoldBadges,
        coalesce(vt.UpVotes, 0) as UpVotesCast,
        coalesce(vt.DownVotes, 0) as DownVotesCast
    from Users u
    left join (
        select OwnerUserId, count(*) as QuestionsAsked
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) qs on qs.OwnerUserId = u.Id
    left join (
        select OwnerUserId, count(*) as AnswersGiven
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) ans on ans.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as CommentsMade
        from Comments
        group by UserId
    ) comm on comm.UserId = u.Id
    left join (
        select 
            UserId,
            sum(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges,
            sum(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
            sum(case when Class = 1 then BadgeCount else 0 end) as GoldBadges
        from UserBadgeCounts
        group by UserId
    ) ub on ub.UserId = u.Id
    left join (
        select 
            UserId, 
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by UserId
    ) vt on vt.UserId = u.Id
)
select 
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.CommentsMade,
    uas.BronzeBadges,
    uas.SilverBadges,
    uas.GoldBadges,
    uas.UpVotesCast,
    uas.DownVotesCast,
    coalesce(dq.OriginalQuestionTitle, 'No duplicates') as DuplicateOriginalQuestion,
    coalesce(dq.DuplicateQuestionTitle, 'No duplicates') as DuplicateTitle,
    coalesce(qcr.CloseReason, 'Not Closed') as LastCloseReason,
    qcr.LastCloseDate,
    tt.TagName as MostFrequentHighScoreTag,
    tt.PostScore,
    SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) OVER (PARTITION BY uas.Id) AS CloseReopenEvents,
    max(ph.CreationDate) as LastPostEditDate,
    rn.Rank
from UserActivitySummary uas
left join DuplicateQuestions dq on dq.PostId = (
    select p.Id from Posts p where p.OwnerUserId = uas.Id and p.PostTypeId=1 order by p.CreationDate desc limit 1
)
left join QuestionCloseReasons qcr on qcr.PostId = (
    select p.Id from Posts p where p.OwnerUserId = uas.Id and p.PostTypeId=1 order by p.CreationDate desc limit 1
)
left join (
    select distinct on (t.Id) t.Id, t.TagName, t.Count, p.Score as PostScore, p.OwnerUserId
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like '%' || t.TagName || '%'
    order by t.Id, p.Score desc nulls last
) tt on tt.OwnerUserId = uas.Id
left join PostHistory ph on ph.UserId = uas.Id
left join RecursiveUserActivity rn on rn.UserId = uas.Id
where uas.Reputation > 1000
order by uas.Reputation desc, uas.QuestionsAsked desc
limit 50;