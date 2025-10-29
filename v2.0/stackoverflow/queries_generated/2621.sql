-- {"query": "2621.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1443} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        b.TagBased,
        row_number() over (partition by u.Id order by b.Date desc, b.Class, b.Name) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date is not null
), 
TopUsersByBadgeCount as (
    select 
        UserId,
        DisplayName,
        count(*) as TotalBadges,
        sum(case when BadgeClass = 1 then 1 else 0 end) as GoldBadges,
        sum(case when BadgeClass = 2 then 1 else 0 end) as SilverBadges,
        sum(case when BadgeClass = 3 then 1 else 0 end) as BronzeBadges
    from RecursiveUserBadges
    group by UserId, DisplayName
    having count(*) > 5
),
LatestPostsCTE as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.OwnerUserId,
        p.Tags,
        p.AcceptedAnswerId,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank
    from Posts p
    where p.PostTypeId in (1,2) -- questions or answers
),
UserQuestionAnswerStats as (
    select 
        u.Id as UserId,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        avg(case when p.PostTypeId = 1 then p.Score else null end) as AvgQuestionScore,
        avg(case when p.PostTypeId = 2 then p.Score else null end) as AvgAnswerScore,
        sum(case when p.PostTypeId = 1 and p.AcceptedAnswerId is not null then 1 else 0 end) as QuestionsWithAcceptedAnswer
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    group by u.Id
),
UserVoteActivity as (
    select
        v.UserId,
        count(*) as TotalVotesCast,
        count(case when vt.Name = 'UpMod' then 1 end) as UpVotesCast,
        count(case when vt.Name = 'DownMod' then 1 end) as DownVotesCast,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    inner join VoteTypes vt on v.VoteTypeId = vt.Id
    where v.UserId is not null
    group by v.UserId
),
DuplicatedQuestions as (
    select distinct pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
QuestionClosureStats as (
    select 
        ph.PostId,
        count(case when pht.Name = 'Post Closed' then 1 end) as CloseVotesCount,
        max(ph.CreationDate) as LastClosedDate,
        max(crt.Name) filter (where pht.Name = 'Post Closed') as LastCloseReason
    from PostHistory ph
    inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on ph.Comment::int = crt.Id
    group by ph.PostId
),
TagUsageFrequency as (
    select 
        tagname,
        sum(count) as TotalCount
    from (
        select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as tagname, p.Id as PostId
        from Posts p
        where p.PostTypeId = 1 and p.Tags is not null
    ) tagExtract
    inner join Tags t on lower(t.TagName) = lower(tagExtract.tagname)
    group by tagname
    order by TotalCount desc
    limit 10
)
select 
    u.Id as UserId,
    u.DisplayName,
    coalesce(us.QuestionCount,0) as QuestionCount,
    coalesce(us.AnswerCount,0) as AnswerCount,
    coalesce(us.AvgQuestionScore,0) as AvgQuestionScore,
    coalesce(us.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(us.QuestionsWithAcceptedAnswer,0) as QuestionsWithAcceptedAnswer,
    coalesce(vote.TotalVotesCast,0) as VotesCast,
    coalesce(vote.UpVotesCast,0) as UpVotesCast,
    coalesce(vote.DownVotesCast,0) as DownVotesCast,
    tb.TotalBadges,
    tb.GoldBadges,
    tb.SilverBadges,
    tb.BronzeBadges,
    dup.DuplicateQuestionId,
    dup.OriginalQuestionId,
    qc.CloseVotesCount,
    qc.LastClosedDate,
    qc.LastCloseReason,
    -- Example of complicated string expression and null logic
    case 
        when u.Location is null then 'Unknown'
        when u.Location like '%USA%' or u.Location like '%United States%' then 'USA'
        else u.Location 
    end as NormalizedLocation,
    -- Using window function to rank users by reputation ignoring nulls & duplicates checked
    rank() over (order by u.Reputation desc nulls last) as ReputationRank,
    -- Correlated subquery: count of comments by user on their own posts (only distinct post IDs)
    (select count(distinct c.PostId) from Comments c where c.UserId = u.Id and exists (select 1 from Posts p2 where p2.Id = c.PostId and p2.OwnerUserId = u.Id)) as SelfCommentedPostCount
from Users u
left join UserQuestionAnswerStats us on us.UserId = u.Id
left join UserVoteActivity vote on vote.UserId = u.Id
left join TopUsersByBadgeCount tb on tb.UserId = u.Id
left join DuplicatedQuestions dup on dup.DuplicateQuestionId = us.QuestionCount > 0 and dup.DuplicateQuestionId = (
    select min(p.Id) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1
) or dup.DuplicateQuestionId is null
left join QuestionClosureStats qc on qc.PostId = (
    select min(p.Id) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1
)
where u.Reputation > 1000 and u.LastAccessDate > now() - interval '180 days'
order by ReputationRank
limit 100;