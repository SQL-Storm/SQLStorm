-- {"query": "2910.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1593}
with recursive RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        p.OwnerUserId,
        p.CreationDate
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    union all
    select
        rtc.TagId,
        rtc.TagName,
        rtc.AnswerCount + coalesce(p2.AnswerCount,0) as AnswerCount,
        p2.OwnerUserId,
        p2.CreationDate
    from RecursiveTagCounts rtc
    join Posts p2 on p2.OwnerUserId = rtc.OwnerUserId and p2.PostTypeId = 1
    where p2.CreationDate > rtc.CreationDate
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        sum(coalesce(vp.Score, 0)) as TotalVoteScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join (
        select Id as PostId, sum(coalesce(Score,0)) as Score
        from Posts
        group by Id
    ) vp on vp.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation
),
LatestCommentsPerPost as (
    select
        c.PostId,
        c.Id as CommentId,
        c.CreationDate,
        c.UserId as CommentUserId,
        u.DisplayName as CommentUserName,
        c.Text as CommentText
    from (
        select c.*, row_number() over (partition by c.PostId order by c.CreationDate desc) as rn
        from Comments c
    ) c
    left join Users u on u.Id = c.UserId
    where c.rn = 1
),
AcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerCreationDate,
        a.OwnerUserId as AcceptedAnswerOwnerUserId,
        au.DisplayName as AcceptedAnswerOwnerName
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users au on au.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
UserBadges as (
    select
        UserId,
        Name,
        Class,
        Date,
        row_number() over (partition by UserId order by Date desc) as rn
    from Badges
),
CloseVotesCounts as (
    select
        ph.PostId,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotes,
        sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenVotes
    from PostHistory ph
    group by ph.PostId
),
TagNameSplit as (
    select
        p.Id as PostId,
        trim(both '<>' from unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null and char_length(p.Tags) > 2
),
FilteredPosts as (
    select p.Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId, p.CreationDate, p.PostTypeId, p.Tags, u.DisplayName
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2) and p.Score > 5 and p.ViewCount > 50
),
ComplexRanking as (
    select
        fp.Id as PostId,
        fp.Title,
        fp.Score,
        fp.ViewCount,
        fp.OwnerUserId,
        fp.DisplayName as OwnerDisplayName,
        row_number() over (partition by fp.PostTypeId order by fp.Score desc, fp.ViewCount desc) as RankWithinType,
        ntot.TotalCount as TotalPostsOfType,
        cv.CloseVotes,
        cv.ReopenVotes,
        coalesce(ac.AcceptedAnswerScore, 0) as AcceptedAnswerScore,
        ac.AcceptedAnswerId,
        ac.AcceptedAnswerOwnerUserId,
        coalesce(lb.Name, 'None') as LastBadgeName,
        coalesce(lcp.CommentText, 'No Comments') as LatestCommentText,
        coalesce(tag.TagName, 'NoTags') as AssociatedTag
    from FilteredPosts fp
    left join CloseVotesCounts cv on cv.PostId = fp.Id
    left join AcceptedAnswers ac on ac.QuestionId = fp.Id and fp.PostTypeId = 1
    left join UserBadges lb on lb.UserId = fp.OwnerUserId and lb.rn = 1
    left join LatestCommentsPerPost lcp on lcp.PostId = fp.Id
    left join TagNameSplit tag on tag.PostId = fp.Id
    cross join lateral (
        select count(*) as TotalCount
        from Posts p2
        where p2.PostTypeId = fp.PostTypeId
    ) ntot
),
FinalRankings as (
    select
        cr.PostId,
        cr.Title,
        cr.Score,
        cr.ViewCount,
        cr.OwnerUserId,
        cr.OwnerDisplayName,
        cr.RankWithinType,
        cr.TotalPostsOfType,
        cr.CloseVotes,
        cr.ReopenVotes,
        cr.AcceptedAnswerScore,
        cr.AcceptedAnswerId,
        cr.AcceptedAnswerOwnerUserId,
        cr.LastBadgeName,
        cr.LatestCommentText,
        cr.AssociatedTag,
        rank() over (order by 
            case when cr.CloseVotes > 0 then 0 else 1 end desc,
            cr.RankWithinType asc,
            cr.Score desc,
            cr.ViewCount desc
        ) as OverallRank
    from ComplexRanking cr
)
select
    fr.OverallRank,
    fr.PostId,
    fr.Title,
    fr.Score,
    fr.ViewCount,
    fr.OwnerUserId,
    fr.OwnerDisplayName,
    fr.CloseVotes,
    fr.ReopenVotes,
    fr.AcceptedAnswerId,
    fr.AcceptedAnswerScore,
    fr.AcceptedAnswerOwnerUserId,
    fr.LastBadgeName,
    substr(fr.LatestCommentText, 1, 100) as LatestCommentExcerpt,
    fr.AssociatedTag,
    up.QuestionCount,
    up.AnswerCount,
    up.Reputation,
    up.TotalVoteScore,
    up.UpVotes,
    up.DownVotes,
    case
        when up.Reputation > 10000 then 'High Rep'
        when up.Reputation > 1000 then 'Medium Rep'
        else 'Low Rep'
    end as ReputationCategory,
    (select count(*) from Posts p where p.OwnerUserId = fr.OwnerUserId and p.PostTypeId = 1 and p.CreationDate between (date '2024-10-01' - interval '365 days') and date '2024-10-01') as QuestionsLastYear,
    (select count(*) from Posts p where p.OwnerUserId = fr.OwnerUserId and p.PostTypeId = 2 and p.CreationDate between (date '2024-10-01' - interval '365 days') and date '2024-10-01') as AnswersLastYear
from FinalRankings fr
left join UserPostStats up on up.UserId = fr.OwnerUserId
where fr.OverallRank <= 50
order by fr.OverallRank;