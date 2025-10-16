-- {"query": "1130.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1810} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        coalesce(array_agg(pt.Name) filter (where pt.Name is not null), array[]::varchar[]) as PostTypeNames,
        t.Count,
        1 as Level
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    left join PostTypes pt on pt.Id = p.PostTypeId
    group by t.Id, t.TagName, t.Count
    union all
    select 
        rth.Id,
        rth.TagName,
        rth.PostTypeNames,
        rth.Count,
        rth.Level + 1
    from RecursiveTagHierarchy rth
    join Tags t2 on t2.Id = rth.Id
    where rth.Level < 1
),

UserActivityDetails as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(vote_up.VoteCount) as TotalUpVotes,
        sum(vote_down.VoteCount) as TotalDownVotes,
        max(p.Score) as MaxPostScore,
        rank() over (order by u.Reputation desc, QuestionCount desc, AnswerCount desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 2 -- UpMod
        group by PostId
    ) vote_up on vote_up.PostId = p.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 3 -- DownMod
        group by PostId
    ) vote_down on vote_down.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation
),

AcceptedAnswerAge as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreation,
        extract(epoch from (a.CreationDate - q.CreationDate))/3600 as HoursToAccept
    from Posts q
    join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
),

CloseVotesSummary as (
    select
        ph.PostId,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseVoteCount
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, ph.Comment, crt.Name
),

UserBadging as (
    select 
        b.UserId, 
        b.Name as BadgeName,
        b.Class,
        b.TagBased,
        count(*) over (partition by b.UserId) as TotalBadges,
        row_number() over (partition by b.UserId order by b.Date desc) as RecentBadgeRank
    from Badges b
    where b.Class in (1,2,3)
),

UserPostWindowStats as (
    select
        p.OwnerUserId,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        avg(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between 4 preceding and current row) as AvgRecent5Scores,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank
    from Posts p
    where p.OwnerUserId is not null
),

CombinedUserStats as (
    select
        uad.UserId,
        uad.DisplayName,
        uad.Reputation,
        uad.QuestionCount,
        uad.AnswerCount,
        uad.CommentCount,
        uad.TotalUpVotes,
        uad.TotalDownVotes,
        max(uad.MaxPostScore) as MaxPostScore,
        count(distinct ub.BadgeName) as DistinctBadgeCount,
        coalesce(avg(ups.AvgRecent5Scores),0) as AverageRecentScore
    from UserActivityDetails uad
    left join UserBadging ub on ub.UserId = uad.UserId and ub.RecentBadgeRank <= 5
    left join UserPostWindowStats ups on ups.OwnerUserId = uad.UserId and ups.RecentPostRank <= 10
    group by 
        uad.UserId, uad.DisplayName, uad.Reputation, uad.QuestionCount,
        uad.AnswerCount, uad.CommentCount, uad.TotalUpVotes, uad.TotalDownVotes
),

DuplicateLinksQuestions as (
    select distinct
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on pl.PostId = p1.Id and p1.PostTypeId = 1
    join Posts p2 on pl.RelatedPostId = p2.Id and p2.PostTypeId = 1
    where pl.LinkTypeId = 3 -- Duplicate
),

TopDuplicates as (
    select
        dq.DuplicateQuestionId,
        dq.OriginalQuestionId,
        dq.CreationDate,
        row_number() over (partition by dq.OriginalQuestionId order by dq.CreationDate) as DuplicateRank
    from DuplicateLinksQuestions dq
),

LastFiveCommentsWithNullLogic as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.Text,
        c.CreationDate,
        coalesce(u.DisplayName, c.UserDisplayName, 'anonymous') as CommentAuthor,
        case 
            when c.Score is NULL then 0
            else c.Score
        end as CommentScore
    from Comments c
    left join Users u on u.Id = c.UserId
    order by c.PostId, c.CreationDate desc
),

FinalTagInterestByUser as (
    select 
        u.Id as UserId,
        u.DisplayName,
        array_agg(distinct regexp_split_to_table(substring(p.Tags from 2 for length(p.Tags)-2), '[><]')) as TagList
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    where u.Reputation > 1000
    group by u.Id, u.DisplayName
)

select 
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.QuestionCount,
    c.AnswerCount,
    c.CommentCount,
    c.TotalUpVotes,
    c.TotalDownVotes,
    c.MaxPostScore,
    c.DistinctBadgeCount,
    round(c.AverageRecentScore, 2) as AverageRecentScore,
    string_agg(distinct dt.TagName, ', ') filter (where dt.Level = 1) as TagsInterested,
    aa.HoursToAccept,
    cv.CloseReasonName,
    cv.CloseVoteCount,
    dt.Level as TagHierarchyLevel,
    lc.CommentAuthor,
    substring(lc.Text from 1 for 60) || case when length(lc.Text) > 60 then '...' else '' end as RecentCommentSnippet,
    dup.OriginalQuestionId,
    dup.DuplicateRank
from CombinedUserStats c
left join FinalTagInterestByUser fti on fti.UserId = c.UserId
left join RecursiveTagHierarchy dt on dt.TagName = any(fti.TagList)
left join AcceptedAnswerAge aa on aa.QuestionId = (
    select p.Id from Posts p where p.AcceptedAnswerId is not null and p.OwnerUserId = c.UserId limit 1)
left join CloseVotesSummary cv on cv.PostId = aa.QuestionId
left join LastFiveCommentsWithNullLogic lc on lc.PostId = aa.QuestionId
left join TopDuplicates dup on dup.DuplicateQuestionId = aa.QuestionId
where c.QuestionCount > 5 and c.TotalUpVotes > c.TotalDownVotes
order by c.Reputation desc, c.QuestionCount desc, c.AnswerCount desc
limit 50;