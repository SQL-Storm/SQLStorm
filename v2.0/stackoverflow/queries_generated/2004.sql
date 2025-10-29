-- {"query": "2004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1661} 
with RecursiveUserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.Score) as TotalPostScore,
        row_number() over (partition by u.Location order by sum(p.Score) desc nulls last) as ScoreRankInLocation,
        dense_rank() over (order by u.Reputation desc nulls last) as ReputationRank,
        coalesce(array_agg(distinct b.Name order by b.Date desc) filter (where b.Class = 1), ARRAY[]::varchar[]) as GoldBadges,
        coalesce(array_agg(distinct b.Name order by b.Date desc) filter (where b.Class = 2), ARRAY[]::varchar[]) as SilverBadges,
        coalesce(array_agg(distinct b.Name order by b.Date desc) filter (where b.Class = 3), ARRAY[]::varchar[]) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Location, u.Reputation
),
TopQuestionPosts as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName as OwnerName,
        -- Extract the most frequent tag from Tags array
        (select tag from unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as tag
         group by tag order by count(*) desc limit 1) as MostFrequentTag
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
        and p.CreationDate > now() - interval '1 year'
),
AnswerVotesCte as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        (count(v.Id) filter (where v.VoteTypeId = 2) - count(v.Id) filter (where v.VoteTypeId = 3)) as NetVotes
    from Posts a
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId = 2
    group by a.Id, a.ParentId
),
CommentAgg as (
    select
        c.PostId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        bool_or(c.Text is null) as HasNullCommentText,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ',' order by c.CreationDate desc) as CommenterNamesConcat
    from Comments c
    group by c.PostId
),
PostWithDetails as (
    select
        q.QuestionId,
        q.Title,
        q.MostFrequentTag,
        q.OwnerUserId,
        q.OwnerName,
        q.Score,
        q.ViewCount,
        q.CreationDate as QuestionCreationDate,
        a.AnswerId,
        a.UpVotes,
        a.DownVotes,
        a.NetVotes,
        cu.CommentCount,
        cu.LastCommentDate,
        cu.HasNullCommentText,
        cu.CommenterNamesConcat,
        rus.QuestionCount,
        rus.AnswerCount,
        rus.TotalPostScore,
        rus.ScoreRankInLocation,
        rus.ReputationRank,
        rus.GoldBadges,
        rus.SilverBadges,
        rus.BronzeBadges
    from TopQuestionPosts q
    left join AnswerVotesCte a on a.QuestionId = q.QuestionId
    left join CommentAgg cu on cu.PostId = q.QuestionId
    left join RecursiveUserStats rus on rus.UserId = q.OwnerUserId
),
RankedPosts as (
    select
        *,
        rank() over (partition by MostFrequentTag order by Score desc nulls last) as TagScoreRank,
        rank() over (partition by OwnerUserId order by QuestionCreationDate desc) as RecentQuestionRank
    from PostWithDetails
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(*) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
FinalSelection as (
    select
        rp.QuestionId,
        rp.Title,
        rp.MostFrequentTag,
        rp.OwnerUserId,
        rp.OwnerName,
        rp.Score,
        rp.ViewCount,
        rp.QuestionCreationDate,
        coalesce(dl.DuplicateCount, 0) as DuplicateLinks,
        rp.AnswerId,
        rp.UpVotes,
        rp.DownVotes,
        rp.NetVotes,
        rp.CommentCount,
        rp.LastCommentDate,
        rp.HasNullCommentText,
        rp.CommenterNamesConcat,
        rp.QuestionCount,
        rp.AnswerCount,
        rp.TotalPostScore,
        rp.ScoreRankInLocation,
        rp.ReputationRank,
        rp.GoldBadges,
        rp.SilverBadges,
        rp.BronzeBadges,
        rp.TagScoreRank,
        rp.RecentQuestionRank
    from RankedPosts rp
    left join DuplicateLinkCounts dl on dl.PostId = rp.QuestionId
    where rp.ScoreRankInLocation <= 10
      and rp.TagScoreRank <= 5
      and (rp.RecentQuestionRank = 1 or rp.NetVotes > 10)
)
select
    fs.QuestionId,
    fs.Title,
    fs.MostFrequentTag,
    fs.OwnerName,
    fs.Score,
    fs.ViewCount,
    to_char(fs.QuestionCreationDate, 'YYYY-MM-DD') as QuestionDate,
    fs.DuplicateLinks,
    fs.AnswerId,
    fs.UpVotes,
    fs.DownVotes,
    fs.NetVotes,
    fs.CommentCount,
    fs.LastCommentDate,
    fs.HasNullCommentText,
    fs.CommenterNamesConcat,
    fs.QuestionCount,
    fs.AnswerCount,
    fs.TotalPostScore,
    fs.ScoreRankInLocation,
    fs.ReputationRank,
    array_to_string(fs.GoldBadges, ', ') as GoldBadges,
    array_to_string(fs.SilverBadges, ', ') as SilverBadges,
    array_to_string(fs.BronzeBadges, ', ') as BronzeBadges,
    fs.TagScoreRank,
    fs.RecentQuestionRank,
    -- Correlated subquery: latest post history edit comment for question
    (select ph.Comment
     from PostHistory ph
     where ph.PostId = fs.QuestionId
       and ph.PostHistoryTypeId in (4,5)
     order by ph.CreationDate desc limit 1) as LatestEditComment,
    -- Expression with NULL logic and string concatenation
    ('User: ' || coalesce(fs.OwnerName, 'Unknown') || ' has ' ||
     coalesce(cast(fs.QuestionCount as varchar), '0') || ' questions and ' ||
     coalesce(cast(fs.AnswerCount as varchar), '0') || ' answers.') as UserSummary,
    -- Conditional calculation
    case
        when fs.ViewCount > 10000 then 'Hot'
        when fs.Score >= 50 then 'Popular'
        else 'Normal'
    end as PostPopularityStatus
from FinalSelection fs
order by fs.ReputationRank, fs.Score desc, fs.ViewCount desc
limit 100;